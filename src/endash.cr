require "./endash/*"
require "http-router"
require "http/server"
require "lemur"
require "geode"
require "status_page"
require "crometheus"

ASS_VERSION = "1"

Lemur.repeated_flag(host, EnDash::Host, "A host to connect to")

module Template
  macro render_layout(context, filename, layout)
    __content_filename__ = {{filename}}
    content_io = IO::Memory.new
    ECR.embed {{ filename }}, content_io
    content = content_io.to_s
    layout_io = IO::Memory.new
    ECR.embed {{ layout }}, layout_io
    context.response.content_type = "text/html"
    layout_io.rewind
    IO.copy layout_io, context.response
  end
end

class EnDash::Handler
  include HTTP::Handler

  include Template
  include HTTP::Router

  @watchers : Array(EnDash::Watcher)

  def initialize(spindle, hosts : Array(EnDash::Host))
    @watchers = hosts.map do |host|
      EnDash::Watcher.new host, spindle
    end
  end

  @[HTTP::Route(path: "/stop", method: :POST)]
  private def stop_container(context)
    unless body = context.request.body
      raise "no body"
    end
    req = NamedTuple(container: String, host: String).from_json(body)
    unless watcher = @watchers.find { |w| w.host.name == req[:host] }
      context.not_found "no host: #{req[:host]}"
      return
    end

    watcher.stop_container(req[:container])

    context.ok_json(
      text: "✅",
      invalidate: true,
    )
  end

  @[HTTP::Route(path: "/bounce", method: :POST)]
  private def bounce_container(context)
    unless body = context.request.body
      raise "no body"
    end
    req = NamedTuple(container: String, host: String).from_json(body)
    unless watcher = @watchers.find { |w| w.host.name == req[:host] }
      raise "no host: #{req[:host]}"
    end

    watcher.restart_container(req[:container])

    context.ok_json(text: "✅")
  end

  @[HTTP::Route(path: "/prometheus", method: :GET)]
  private def handle_prometheus(context)
    containers = [] of EnDash::Container

    Geode::Spindle.run do |spindle|
      @watchers.each do |w|
        spindle.spawn do
          containers.concat w.get_containers_with_cache
        rescue ex : Exception
          Log.error(exception: ex) { "Failed to get containers for #{w}" }
        end
      end
    end

    context.ok_json containers.map(&.as_service).reject(&.nil?)
  end

  @[HTTP::Route(path: "/logs", method: :GET)]
  def handle_logs(context)
    id = context.query_string("id")
    host = context.query_string("host")
    unless watcher = @watchers.find { |w| w.host.name == host }
      context.fail HTTP::Status::BAD_REQUEST, "no host named #{host}"
      return
    end

    Log.info { "loading #{host}/#{id}" }

    unless container = watcher.get_container(id)
      context.not_found "no such container: #{id}"
      return
    end

    context.ok_text watcher.get_logs(id)
  end

  @[HTTP::Route(path: "/", method: :GET)]
  private def handle_index(context)
    host = context.request.query_params["host"]?
    title = host.nil? ? "endash" : "endash-#{HTML.escape host}"

    containers = [] of EnDash::Container
    Geode::Spindle.run do |spindle|
      @watchers.each do |w|
        next unless host.nil? || w.host.name == host
        spindle.spawn do
          containers.concat w.get_containers
        rescue ex : Exception
          Log.error(exception: ex) { "Failed to get containers for #{w}" }
        end
      end
    end
    containers.sort_by!(&.sort_key)

    render_layout context, "src/templates/index.html", "src/templates/layout.html"
  end

  private def button_class(title)
    if /\d+(:\d+)?/.match title
      "port"
    elsif title == "Status"
      "status"
    elsif title == "Logs"
      "logs"
    else
      "other"
    end
  end

  include StatusPage::Section

  def render(io : IO)
    html io do
      @watchers.each do |watcher|
        table watcher.host.name do
          kv "Container fetches", watcher.stats.container_fetches
          kv "Cached fetches", watcher.stats.cached_fetches
          fetches = watcher.stats.container_fetch_times
          kv "Fetch time", fetches.sum / fetches.size unless fetches.empty?
        end
      end
    end
  end
end

Lemur.init

Log.setup do |l|
  l.stderr
  l.status_page
end

inspector = StatusPage::HTTPSection.new
inspector.register!

Crometheus.default_registry.path = "/metrics"

Geode::Spindle.run do |spindle|
  endash = EnDash::Handler.new(spindle, Lemur.host)
  endash.register!
  server = HTTP::Server.new [
    Crometheus::Middleware::HttpCollector.new,
    inspector,
    HTTP::LogHandler.new,
    HTTP::ErrorHandler.new(verbose: true),
    HTTP::StaticFileHandler.new("/src/src/public", directory_listing: false),
    StatusPage.default_handler,
    Crometheus.default_registry.get_handler,
    endash,
  ]
  server.bind_tcp "0", 80

  spindle.spawn do
    Log.info { "Listening on :80" }
    server.listen
  end
end

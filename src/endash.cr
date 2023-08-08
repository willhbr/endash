require "./endash/*"
require "http/server"
require "lemur"
require "geode"
require "status_page"
require "crometheus"

Lemur.repeated_flag(host, EnDash::Host, "A host to connect to")

module Template
  macro render(context, template)
    %context = {{ context }}
    %context.response.content_type = "text/html"
    __mAgIc_iO__ = %context.response.output
    ECR.embed {{ template }}, __mAgIc_iO__
  end

  macro inline(template)
    ECR.embed {{ template }}, __mAgIc_iO__
  end
end

class EnDash::Handler
  include HTTP::Handler

  include Template

  @watchers : Array(EnDash::Watcher)

  def initialize(spindle, hosts : Array(EnDash::Host))
    @watchers = hosts.map do |host|
      EnDash::Watcher.new host, spindle
    end
  end

  def call(context)
    case context.request.method
    when "GET"
      handle_get(context)
    else
      raise "unknown method"
    end
  end

  private def handle_get(context)
    path = context.request.path
    case path
    when "/"
      handle_index(context)
    when .starts_with? "/info"
      handle_info(context)
    when "/prometheus"
      handle_prometheus(context)
    else
      parts = path.split('/')
      unless parts.size > 2
        respond_error context, HTTP::Status::NOT_FOUND, "not found"
        return
      end
      unless tup = self.get_host_container(path)
        respond_error context, HTTP::Status::NOT_FOUND, "not found"
        return
      end
      host, container, rest = tup
      context.response.puts "#{host}, #{container}, #{rest}"
    end
  end

  private def handle_prometheus(context)
    containers = [] of EnDash::Container

    spindle = Geode::Spindle.new
    @watchers.each do |w|
      spindle.spawn do
        containers.concat w.get_containers
      end
    end
    spindle.join

    context.response.content_type = "application/json"
    containers.map(&.as_service).reject(&.nil?).to_json(context.response)
  end

  private def get_host_container(path)
    unless h_index = path.index('/', 1)
      return nil
    end
    host = path[1...h_index]
    h_index += 1
    unless c_index = path.index('/', h_index)
      container = path[h_index...]
      return {host, container, "/"}
    end
    container = path[h_index...c_index]
    rest = path[c_index..]
    {host, container, rest}
  end

  private def handle_info(context)
    params = context.request.query_params
    unless (id = params["container"]?) && (host = params["host"]?)
      respond_error context, HTTP::Status::BAD_REQUEST, "missing container param"
      return
    end

    unless watcher = @watchers.find { |w| w.host.name == host }
      respond_error context, HTTP::Status::BAD_REQUEST, "no host named #{host}"
      return
    end

    Log.info { "loading #{host}/#{id}" }

    unless (info = watcher.container_info(id)) && (container = watcher.get_container(id))
      respond_error context, HTTP::Status::NOT_FOUND, "no such container: #{id}"
      return
    end
    image = watcher.get_image? info.image_id

    title = info.name
    logs = watcher.get_logs(id)
    render context, "src/templates/info.html"
  end

  private def attributes(container, image)
    yield "State", container.state.to_s
    yield "Container", container.id.truncated
    yield "Image", container.image_id.truncated
    if container.state.running?
      yield "Started", container.started_at
    else
      yield "Exited", container.exited_at
      yield "Exit code", container.exit_code
    end
    if image
      yield "Built", image.created_at
    end
    container.networks.each do |network|
      yield "Network", network
    end
  end

  private def handle_index(context)
    title = "endash"

    containers = [] of EnDash::Container

    spindle = Geode::Spindle.new
    @watchers.each do |w|
      spindle.spawn do
        containers.concat w.get_containers
      end
    end
    spindle.join
    containers.sort_by!(&.sort_key)

    render context, "src/templates/index.html"
  end

  private def respond_error(context, status, message)
    context.response.status = status
    context.response.puts message
  end

  private def icon_for(container)
    case container.state
    when .running?
      "success"
    when .exited?
      "error"
    else
      "help"
    end
  end

  private def button_class(title)
    if /\d+(:\d+)?/.match title
      "p-button--brand"
    elsif title == "Status"
      "p-button--positive"
    else
      "p-button"
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

spindle = Geode::Spindle.new

Crometheus.default_registry.path = "/metrics"

server = HTTP::Server.new [
  Crometheus::Middleware::HttpCollector.new,
  inspector,
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new(verbose: true),
  HTTP::StaticFileHandler.new("/src/src/public", directory_listing: false),
  StatusPage.default_handler,
  Crometheus.default_registry.get_handler,
  EnDash::Handler.new(spindle, Lemur.host),
]
server.bind_tcp "0", 80

spindle.spawn do
  Log.info { "Listening on :80" }
  server.listen
end

spindle.join

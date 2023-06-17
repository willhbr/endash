require "./endash/*"
require "http/server"
require "geode"
require "status_page"

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

  def initialize(spindle)
    @host = EnDash::Host.new("Tycho", "tycho", "unix:///run/user/podman/podman.sock")
    @watcher = EnDash::Watcher.new(@host, spindle)
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
    case context.request.path
    when "/"
      handle_index(context)
    when .starts_with? "/info"
      handle_info(context)
    else
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.puts "not found"
    end
  end

  private def handle_info(context)
    params = context.request.query_params
    unless (id = params["container"]?) && (host = params["host"]?)
      respond_error context, HTTP::Status::BAD_REQUEST, "missing container param"
      return
    end

    Log.info { "loading #{host}/#{id}" }

    unless (info = @watcher.container_info(id)) && (container = @watcher.get_container(id))
      respond_error context, HTTP::Status::NOT_FOUND, "no such container: #{id}"
      return
    end
    image = @watcher.get_image? info.image_id

    title = info.name
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
  end

  private def handle_index(context)
    title = "endash"

    containers = @watcher.get_containers
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

Log.setup do |l|
  l.stderr
  l.status_page
end

inspector = StatusPage::HTTPSection.new
inspector.register!

spindle = Geode::Spindle.new

server = HTTP::Server.new [
  inspector,
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new,
  HTTP::StaticFileHandler.new("/src/src/public", directory_listing: false),
  StatusPage.default_handler,
  EnDash::Handler.new(spindle),
]
server.bind_tcp "0", 80

spindle.spawn do
  Log.info { "Listening on :80" }
  server.listen
end

spindle.join

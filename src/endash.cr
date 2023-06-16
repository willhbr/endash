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
    else
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.puts "not found"
    end
  end

  private def handle_index(context)
    title = "endash"

    watcher = EnDash::Watcher.new(
      EnDash::Host.new("Tycho", "tycho", "unix:///run/user/podman/podman.sock"))
    containers = watcher.get_containers
    render context, "src/templates/index.html"
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

server = HTTP::Server.new [
  inspector,
  HTTP::LogHandler.new,
  HTTP::ErrorHandler.new,
  HTTP::StaticFileHandler.new("/src/src/public", directory_listing: false),
  StatusPage.default_handler,
  EnDash::Handler.new,
]
server.bind_tcp "0", 80

Log.info { "Listening on :80" }
server.listen

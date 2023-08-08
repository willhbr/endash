require "json"

class String
  def truncated
    self[..12]
  end
end

enum Podman::State
  Configured
  Created
  Running
  Paused
  Stopped
  Exited
end

class Podman::Container
  include JSON::Serializable

  @[JSON::Field(key: "Id")]
  getter id : String
  @[JSON::Field(key: "Image")]
  getter image : String
  @[JSON::Field(key: "ImageID")]
  getter image_id : String
  @[JSON::Field(key: "Names")]
  getter names : Array(String)

  def name
    @names.first.not_nil!
  end

  @[JSON::Field(key: "StartedAt", converter: Time::EpochConverter)]
  getter started_at : Time
  @[JSON::Field(key: "AutoRemove")]
  getter auto_remove : Bool

  @[JSON::Field(key: "ExitCode")]
  getter exit_code : Int32
  @[JSON::Field(key: "ExitedAt", converter: Time::EpochConverter)]
  getter exited_at : Time

  @[JSON::Field(key: "Networks")]
  getter networks : Set(String)

  def uptime_or_downtime : Time::Span
    if @state.exited?
      self.downtime
    else
      self.uptime
    end
  end

  def downtime
    Time.utc - @exited_at
  end

  def uptime : Time::Span
    Time.utc - @started_at
  end

  @[JSON::Field(key: "State")]
  getter state : State

  @[JSON::Field(key: "Labels")]
  getter _labels : Hash(String, String)?

  struct Port
    include JSON::Serializable
    @[JSON::Field(key: "host_port")]
    getter host_port : Int32
    @[JSON::Field(key: "container_port")]
    getter container_port : Int32
  end

  @[JSON::Field(key: "Ports")]
  getter _ports : Array(Port)?

  def labels
    @_labels ||= Hash(String, String).new
  end

  def ports
    @_ports ||= Array(Port).new
  end
end

class EnDash::Container
  getter host
  getter labels : Array(Tuple(String, String))

  def initialize(@host : Host, @container : Podman::Container)
    @labels = Container.calculate_labels(@host, @container)
  end

  def links : Enumerable(Tuple(String, URI))
    unless @container.state.running?
      return [] of Tuple(String, URI)
    end
    default_links = Hash(Int32, Tuple(String, URI)).new
    @container.ports.each do |port|
      uri = URI.new(scheme: "http", host: @host.hostname, port: port.host_port)
      title = if port.host_port == port.container_port
                port.container_port.to_s
              else
                "#{port.host_port}:#{port.container_port}"
              end
      link = {title, uri}
      default_links[port.container_port] = link
    end

    links = Array(Tuple(String, URI)).new
    container_port_to_host_port = @container.ports.to_h { |p| {p.container_port, p.host_port} }
    if extra_links = @container.labels["endash.links"]?
      begin
        Array(NamedTuple(name: String, port: Int32, path: String?)).from_json(
          extra_links).each do |link|
          port = container_port_to_host_port[link[:port]]? || link[:port]
          uri = URI.new(scheme: "http", host: @host.hostname, port: port, path: link[:path] || "")
          links << {link[:name], uri}
          if link[:path].nil?
            # remove default links if we've labelled the same one
            default_links.delete link[:port]
          end
        end
      rescue err : JSON::ParseException
        Log.error(exception: err) { "Failed to parse endash.links on #{@container.name}" }
      end
    end
    links.concat default_links.values
    return links
  end

  private def default_links
  end

  struct Service
    include JSON::Serializable
    getter targets = Array(String).new
    getter labels = Hash(String, String).new

    def initialize(@targets, @labels)
    end
  end

  def as_service : Service?
    unless @container.state.running?
      return nil
    end
    target = @container.labels["prometheus.target"]?
    if target.nil?
      unless port = @container.labels["prometheus.port"]?.try &.to_i
        return nil
      end
      unless pconf = @container.ports.find { |prt| prt.container_port == port }
        Log.error { "No port found for #{port} on #{@container.name}" }
        return nil
      end
      target = "#{@host.hostname}:#{pconf.host_port}"
    end
    labels = {
      "host"         => @host.name.downcase,
      "job"          => @container.name,
      "container_id" => @container.id.truncated,
    }
    begin
      if text = @container.labels["prometheus.labels"]?
        labels.merge! Hash(String, String).from_json(text)
      end
    rescue err : JSON::ParseException
      Log.error(exception: err) { "Failed to parse prometheus.labels on #{@container.name}" }
    end
    Service.new(
      targets: [target],
      labels: labels
    )
  end

  forward_missing_to @container

  def self.calculate_labels(host, container : Podman::Container)
    full_image = container.image
    if idx = full_image.rindex('/')
      repo = full_image[...idx]
    else
      repo = "localhost"
      idx = -1
    end
    img_tag = full_image[(idx + 1)...]

    labels = [{"--positive", host.name}, {"", repo},
              {"--information", img_tag}]
    if label_text = container.labels["endash.labels"]?
      begin
        labels.concat Array(String).from_json(label_text).map { |l| {"", l} }
      rescue err : JSON::ParseException
        Log.error(exception: err) { "Failed to parse endash.labels on #{container.name}" }
      end
    end
    labels
  end

  def sort_key
    {@container.state.running? ? 0 : 1, @container.uptime}
  end
end

class Podman::ContainerDetails
  include JSON::Serializable
  @[JSON::Field(key: "Id")]
  getter id : String
  @[JSON::Field(key: "Image")]
  getter image_id : String
  @[JSON::Field(key: "ImageName")]
  getter image_name : String
  @[JSON::Field(key: "Name")]
  getter name : String

  class Mount
    include JSON::Serializable
    @[JSON::Field(key: "Source")]
    getter source : String
    @[JSON::Field(key: "Destination")]
    getter destination : String
  end

  @[JSON::Field(key: "Mounts")]
  getter mounts : Array(Mount)?

  class Config
    include JSON::Serializable

    @[JSON::Field(key: "Env")]
    getter environment : Array(String)

    @[JSON::Field(key: "Entrypoint")]
    getter entrypoint : String
  end

  @[JSON::Field(key: "Config")]
  getter config : Config

  forward_missing_to @config

  @[JSON::Field(key: "Args")]
  getter args : Array(String)
end

class EnDash::ContainerInfo
  def initialize(@host : Host, @details : Podman::ContainerDetails)
  end

  def full_arguments
    args = [@details.entrypoint]
    args.concat @details.args
  end

  forward_missing_to @details
end

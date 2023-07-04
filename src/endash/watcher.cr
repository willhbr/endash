class EnDash::Watcher
  getter host

  def initialize(@host : Host, @spindle : Geode::Spindle)
    @images = Hash(String, EnDash::Image).new
    @spindle.spawn do
      sleep 3.seconds
      @images = get_images.to_h { |i| {i.id, i} }
    end
  end

  def get_image?(id : String) : EnDash::Image?
    if @images.empty?
      @images = get_images.to_h { |i| {i.id, i} }
    end
    unless image = @images[id]?
      @spindle.spawn do
        @images = get_images.to_h { |i| {i.id, i} }
      end
      return nil
    end
    image
  end

  def get_images : Array(EnDash::Image)
    Array(Podman::Image).from_json(@host.run(
      %w(image ls --format json))).map do |image|
      EnDash::Image.new(@host, image)
    end
  end

  def get_containers : Array(EnDash::Container)
    Array(Podman::Container).from_json(@host.run(
      %w(container ls -a --format json))).map do |container|
      EnDash::Container.new(@host, container)
    end.sort_by(&.sort_key)
  end

  def get_container(id) : EnDash::Container?
    container = Array(Podman::Container).from_json(@host.run(
      %w(container ls -a --format json) + ["--filter=id=#{id}"])).first
    return nil unless container
    EnDash::Container.new(@host, container)
  end

  def container_info(id) : EnDash::ContainerInfo?
    deets = Array(Podman::ContainerDetails).from_json(@host.run(
      %w(container inspect) + [id])).first
    return nil unless deets
    EnDash::ContainerInfo.new(@host, deets)
  end

  def get_logs(id) : String
    success = true
    output = String.build do |io|
      success = @host.run(["logs", "--tail=1000", id], io: io).success?
    end
    return output if success
    raise Exception.new("getting logs failed: #{output}")
  end
end

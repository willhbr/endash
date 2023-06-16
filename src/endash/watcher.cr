class EnDash::Watcher
  def initialize(@host : Host)
  end

  def get_containers : Array(EnDash::Container)
    Array(Podman::Container).from_json(@host.run(
      %w(container ls -a --format json))).map do |container|
      EnDash::Container.new(@host, container)
    end.sort_by(&.sort_key)
  end
end

require "status_page"
require "crometheus"
require "lemur"

Lemur.flag(ignore_systemd_sleep, Bool, "Ignore systemd-sleep container", false)

class EnDash::Watcher
  FETCH_TIME = ContainerFetchTimes.new(:container_fetch_ms, "Duration in ms to load containers")
  Crometheus.alias ContainerFetchTimes = Crometheus::Histogram[:host]

  getter host
  @containers : Array(EnDash::Container)? = nil
  @last_fetch = Time.utc

  getter stats = Stats.new

  def initialize(@host : Host, @spindle : Geode::Spindle)
  end

  def get_containers : Array(EnDash::Container)
    @last_fetch = Time.utc
    start = Time.utc
    cmd = %w(container ls -a --format json)
    if Lemur.ignore_systemd_sleep
      cmd << "-f"
      cmd << "label!=PODMAN_SYSTEMD_UNIT=sleep.service"
    end
    @containers = containers = Array(Podman::Container).from_json(@host.run(
      cmd)).map do |container|
      EnDash::Container.new(@host, container)
    end.sort_by(&.sort_key)
    duration = Time.utc - start
    FETCH_TIME[host: @host.name].observe duration.total_milliseconds
    @stats.container_fetches += 1
    @stats.container_fetch_times << duration
    containers
  end

  def get_containers_with_cache : Array(EnDash::Container)
    unless container_refresh = @host.container_refresh
      return self.get_containers
    end
    unless containers = @containers
      return self.get_containers
    end
    if @last_fetch + container_refresh < Time.utc
      return self.get_containers
    end
    @stats.cached_fetches += 1
    containers
  end

  def get_container(id) : EnDash::Container?
    container = Array(Podman::Container).from_json(@host.run(
      %w(container ls -a --format json) + ["--filter=id=#{id}"])).first
    return nil unless container
    EnDash::Container.new(@host, container)
  end

  def get_logs(id) : String
    success = true
    output = String.build do |io|
      success = @host.run(["logs", "--tail=1000", id], io: io).success?
    end
    return output if success
    raise Exception.new("getting logs failed: #{output}")
  end

  def stop_container(id)
    @host.run(%w(container stop) + [id])
  end

  def restart_container(id)
    @host.run(%w(container restart) + [id])
  end

  class Stats
    property container_fetches : Int32 = 0
    property cached_fetches : Int32 = 0
    getter container_fetch_times = Geode::CircularBuffer(Time::Span).new(20)
  end
end

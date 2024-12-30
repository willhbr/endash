class EnDash::Host
  include JSON::Serializable
  getter hostname : String
  getter container_refresh : Time::Span? = nil
  getter name
  getter timeout : Time::Span = 3.seconds
  getter ui_shows_cached : Bool = false

  def initialize(@name : String, @hostname, @podman_url : String, @identity : String? = nil)
  end

  def run(extra_args : Enumerable(String)) : String
    args = [] of String
    args << "--remote=true"
    args << "--url=#{@podman_url}"
    if id = @identity
      args << "--identity=#{@identity}"
    end
    args = args.concat extra_args

    Log.debug { "Running: podman #{Process.quote(args)}" }
    process = Process.new("podman", args: args,
      input: Process::Redirect::Close,
      output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    t = @timeout
    timed_out = false
    spawn do
      sleep t
      next if process.terminated?
      timed_out = true
      process.terminate graceful: true
      next if process.terminated?
      sleep t
      process.terminate graceful: false
    end
    output = process.output.gets_to_end.chomp
    error = process.error.gets_to_end.chomp
    unless process.wait.success?
      if timed_out
        raise Exception.new("Command `podman #{Process.quote(args)}` timed out: #{error}")
      else
        raise Exception.new("Command `podman #{Process.quote(args)}` failed: #{error}")
      end
    end
    output
  end

  def run(extra_args : Enumerable(String), io : IO) : Process::Status
    args = [] of String
    args << "--remote=true"
    args << "--url=#{@podman_url}"
    if id = @identity
      args << "--identity=#{@identity}"
    end
    args = args.concat extra_args

    Log.debug { "Running: podman #{Process.quote(args)}" }
    process = Process.new("podman", args: args,
      input: Process::Redirect::Close,
      output: io, error: io)

    process.wait
  end

  def self.from_flag(value : String)
    from_json(value)
  end
end

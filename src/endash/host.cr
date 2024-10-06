class EnDash::Host
  include JSON::Serializable
  getter hostname : String
  getter container_refresh : Time::Span? = nil
  getter name

  def initialize(@name : String, @hostname, @podman_url : String, @identity : String? = nil)
  end

  def run(extra_args : Enumerable(String), timeout : Time::Span? = nil) : String
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
    if t = timeout
      spawn do
        sleep t
        next if process.terminated?
        process.terminate graceful: true
        next if process.terminated?
        sleep t
        process.terminate graceful: false
      end
    end
    output = process.output.gets_to_end.chomp
    error = process.error.gets_to_end.chomp
    unless process.wait.success?
      raise Exception.new("Command `podman #{Process.quote(args)}` failed: #{error}")
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

class EnDash::Host
  getter public_address : String
  getter name

  def initialize(@name : String, @public_address, @podman_url : String, @identity : String? = nil)
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
    output = process.output.gets_to_end.chomp
    error = process.error.gets_to_end.chomp
    unless process.wait.success?
      raise Exception.new("Command `podman #{Process.quote(args)}` failed: #{error}")
    end
    output
  end
end

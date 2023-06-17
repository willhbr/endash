require "json"

class Podman::Image
  include JSON::Serializable
  @[JSON::Field(key: "Id")]
  getter id : String
  @[JSON::Field(key: "Containers")]
  getter containers : Int32

  @[JSON::Field(key: "Created", converter: Time::EpochConverter)]
  getter created_at : Time

  @[JSON::Field(key: "Names")]
  getter names = Array(String).new
end

class EnDash::Image
  def initialize(@host : EnDash::Host, @image : Podman::Image)
  end

  forward_missing_to @image
end

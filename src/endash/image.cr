require "json"
require "podman"

class EnDash::Image
  def initialize(@host : EnDash::Host, @image : Podman::Image)
  end

  forward_missing_to @image
end

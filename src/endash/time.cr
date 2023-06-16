struct Time
  def to_iso8601
    Time::Format::ISO_8601_DATE_TIME.format(self)
  end
end

defprotocol Chorex.Transport.Backend do
  @spec send_msg(t, any()) :: [any()]
  def send_msg(t, msg)
end

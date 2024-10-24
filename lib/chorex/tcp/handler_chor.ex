defmodule Chorex.Tcp.HandlerChor do
  import Chorex

  defchor [Handler, TcpClient] do
    def run(Handler.(config), TcpClient.(sock)) do
      loop(Handler.(config), TcpClient.(sock))
    end

    def loop(Handler.(config), TcpClient.(sock)) do
      TcpClient.read(sock) ~> Handler.(msg)
      Handler.process(msg, config)
      loop(Handler.(config), TcpClient.(sock))
    end
  end
end

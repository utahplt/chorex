defmodule Chorex.Tcp.ClientImpl do
  use Chorex.Tcp.HandlerChor.Chorex, :tcpclient

  def read(sock) do
    :gen_tcp.recv(sock, 0)      # 0 = all available bytes
  end

  def send_over_socket(sock, msg) do
    IO.inspect(msg, label: "[client] msg")
    :gen_tcp.send(sock, msg)
  end

  def shutdown(sock) do
    :gen_tcp.close(sock)
  end
end

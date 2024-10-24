defmodule Chorex.Tcp.AccepterPoolImpl do
  use Chorex.Tcp.ListenerChor.Chorex, :accepterpool

  def accept_and_handle_connection(listen_socket) do
    IO.inspect(listen_socket, label: "[accepter_pool] socket")

    {:ok, socket} = :gen_tcp.accept(listen_socket)

    # startup instance of the handler choreography
    Chorex.start(
      Tcp.HandlerChor.Chorex,
      %{Handler => Tcp.HandlerImpl, TcpClient => Tcp.ClientImpl},
      [%{}, socket]
    )
  end
end

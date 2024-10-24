defmodule Chorex.SocketListener do
  use GenServer

  def init(%{listen_port: port, notify: parent}) do
    GenServer.cast(self(), {:listen, port})
    {:ok, %{notify: parent}}
  end

  def handle_cast({:listen, port}, state) do
	{:ok, lsocket} = listen(port)
    {:ok, socket} = :gen_tcp.accept(lsocket)
    {:noreply, %{notify: state.notify, socket: socket}}
  end

  # Messages get sent here after the :gen_tcp.accept()
  def handle_info({:tcp, _socket, data}, state) do
    term = data
    |> :erlang.list_to_binary()
    |> :erlang.binary_to_term()
    GenServer.cast(state.notify, {:tcp_recv, term})
    {:noreply, state}
  end

  def listen(port) do
    default_options = [
      backlog: 1024,
      nodelay: true,
      send_timeout: 30_000,
      send_timeout_close: true,
      reuseaddr: true
    ]
    :gen_tcp.listen(port, default_options)
  end
end

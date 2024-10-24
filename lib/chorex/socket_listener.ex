defmodule Chorex.SocketListener do
  use GenServer

  def init(%{listen_port: port, notify: parent}) do
    GenServer.cast(self(), {:listen, port})
    {:ok, %{parent: parent}}
  end

  def handle_cast({:listen, port}, state) do
	{:ok, socket} = listen(port)
    GenServer.cast(self(), :listen_loop)
    {:noreply, %{notify: state.notify, socket: socket}}
  end

  def handle_cast(:listen_loop, state) do
    {:ok, bytes} = :gen_tcp.recv(state.socket, 0) # 0 = all bytes
    term = :erlang.binary_to_term(bytes)
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

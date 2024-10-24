defmodule Chorex.SocketListener do
  use GenServer

  def init(%{listen_port: port, notify: parent}) do
    GenServer.cast(self(), {:listen, port})
    {:ok, %{parent: parent}}
  end

  def handle_cast({:listen, port}, %{parent: parent}) do
	{:ok, socket} = listen(port)
    GenServer.cast(parent, {:got_knock, socket})
    {:noreply, %{}}
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

defmodule Chorex.SocketProxy do
  @moduledoc """
  Socket proxy
  """
  use GenServer

  def init(%{listen_port: lport, remote_host: rhost, remote_port: rport}) do
    child = GenServer.start_link(Chorex.SocketListener, %{listen_port: lport, notify: self()})
    timer_ref = Process.send_after(self(), {:try_connect, rhost, rport}, 10)
    {:ok, {:not_ready, %{listener: child, knock_timer: timer_ref}}}
  end

  def handle_call({:new_session, _}, _caller, {:not_ready, _} = state),
    do: {:reply, {:error, :waiting}, state}

  def handle_call({:new_session, token}, _caller, state) do
	{:reply, :ok, state}
  end

  def handle_cast({:tcp_recv, msg}, state) do
    #  TODO: notify listeners for this session
    {:noreply, state}
  end

  def handle_cast({:got_knock, socket}, {:not_ready, st}) do
    Process.cancel_timer(st.knock_timer)
    Process.exit(st.listener, :connected)
    {:noreply, {:ready, socket}}
  end

  def handle_cast({:got_knock, socket}, {:ready, st}) do
    # uh oh... race condition
  end

  def handle_info({:try_connect, host, port}, {:not_ready, st}) do
    case :gen_tcp.connect(host, port, [], 1_000) do
      {:ok, socket} ->
        Process.exit(st.listener, :connected)
        {:noreply, {:ready, socket}}

      {:error, _} ->
        new_timer = Process.send_after(self(), {:try_connect, host, port}, 10)
        {:noreply, {:not_ready, %{st | knock_timer: new_timer}}}
    end
  end
end

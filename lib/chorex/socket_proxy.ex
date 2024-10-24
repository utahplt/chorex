defmodule Chorex.SocketProxy do
  @moduledoc """
  Socket proxy
  """
  require Logger
  use GenServer

  @type config_map :: %{
          listen_port: integer(),
          remote_host: binary(),
          remote_port: integer()
        }

  @type state :: %{
          out_socket: nil | :inet.socket(),
          out_queue: :queue.queue(),
          in_listener: pid(),
          config: config_map()
        }

  @spec init(config_map()) :: {:ok, state()}
  def init(%{listen_port: lport, remote_host: _rhost, remote_port: _rport} = config) do
    {:ok, in_listener} =
      GenServer.start_link(Chorex.SocketListener, %{listen_port: lport, notify: self()})

    send(self(), :try_connect)
    {:ok, %{out_socket: nil, out_queue: :queue.new(), in_listener: in_listener, config: config}}
  end

  def handle_info(:try_connect, %{out_socket: nil} = state) do
    host = if is_binary(state.config.remote_host), do: String.to_charlist(state.config.remote_host), else: state.config.remote_host
    # 500 = timeout in milliseconds
    case :gen_tcp.connect(host, state.config.remote_port, [], 500) do
      {:ok, socket} ->
        schedule_send()
        {:noreply, %{state | out_socket: socket}}

      {:error, _} ->
        send(self(), :try_connect)
        {:noreply, state}
    end
  end

  def handle_info(:flush_queue, state) do
    schedule_send(1_000)

    if :queue.is_empty(state.out_queue) do
      {:noreply, state}
    else
      {:noreply, %{state | out_queue: send_until_empty(state)}}
    end
  end

  def handle_cast({:tcp_recv, msg}, state) do
    IO.inspect(msg, label: "#{inspect self()} [SocketProxy] msg received")
    {:noreply, state}
  end

  def handle_cast({:tcp_send, msg}, state) do
    bytes = :erlang.term_to_binary(msg)
    schedule_send()
    {:noreply, %{state | out_queue: :queue.snoc(state.out_queue, bytes)}}
  end

  def schedule_send() do
    send(self(), :flush_queue)
  end

  def schedule_send(timeout) do
    Process.send_after(self(), :flush_queue, timeout)
  end

  @spec send_until_empty(state()) :: :queue.queue()
  def send_until_empty(%{out_queue: q, out_socket: nil}) do
    # No connection; don't do anything
    q
  end

  def send_until_empty(%{out_queue: q, out_socket: socket} = state) do
    case :queue.out(q) do
      {{:value, m}, new_queue} ->
        with :ok <- :gen_tcp.send(socket, m) do
          send_until_empty(%{state | out_queue: new_queue})
        else
          {:error, e} ->
            Logger.warning("[Chorex.SocketProxy] failed sending packet: #{inspect(e)}")
            q
        end

      {:empty, mt_q} ->
        mt_q
    end
  end
end

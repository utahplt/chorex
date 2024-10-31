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
          net_config: config_map(),
          session_key: binary(),
          config: map()
        }

  @spec init(config_map()) :: {:ok, state()}
  def init(%{listen_port: lport, remote_host: _rhost, remote_port: _rport} = config) do
    {:ok, in_listener} =
      GenServer.start_link(Chorex.SocketListener, %{listen_port: lport, notify: self()})

    send(self(), :try_connect)

    {:ok,
     %{
       out_socket: nil,
       out_queue: :queue.new(),
       in_listener: in_listener,
       net_config: config,
       session_key: nil,
       config: nil
     }}
  end

  def handle_info(:try_connect, %{out_socket: nil} = state) do
    host =
      if is_binary(state.net_config.remote_host),
        do: String.to_charlist(state.net_config.remote_host),
        else: state.net_config.remote_host

    # 500 = timeout in milliseconds
    case :gen_tcp.connect(host, state.net_config.remote_port, [], 500) do
      {:ok, socket} ->
        IO.inspect(self(), label: "connected to remote #{host}:#{state.net_config.remote_port}; I am PID: ")
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

  def handle_info({:chorex, session_key, :meta, {:config, config}}, state) do
    # This message doesn't get forwarded
    {:noreply, %{state | config: config, session_key: session_key}}
  end

  def handle_info({signal, _session_key, _sender, _receiver, _msg} = msg, state)
      when signal in [:chorex, :choice] do
    IO.inspect(msg, label: "#{inspect self()} [SocketProxy] sending msg")
    bytes = :erlang.term_to_binary(msg)
    schedule_send()
    {:noreply, %{state | out_queue: :queue.snoc(state.out_queue, bytes)}}
  end

  def handle_cast({:tcp_recv, {signal, _session_key, _sender, receiver, _body} = msg}, state)
    when signal in [:chorex, :choice] do
    IO.inspect(msg, label: "#{inspect self()} [SocketProxy] msg received")
    send(IO.inspect(state.config[receiver], label: "receiver"), msg)
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
        # IO.inspect(:erlang.binary_to_term(m), label: "#{inspect self()} trying to send packet")
        with :ok <- :gen_tcp.send(socket, m) do
          IO.inspect(:erlang.binary_to_term(m), label: "#{inspect self()} sent packet")
          send_until_empty(%{state | out_queue: new_queue})
        else
          {:error, e} ->
            Logger.warning("[Chorex.SocketProxy] failed sending packet: #{inspect(e)}")
            # IO.inspect(m, label: "sending")
            q
        end

      {:empty, mt_q} ->
        mt_q
    end
  end
end

defmodule Chorex.Proxy do
  @moduledoc """
  Proxy for singletons in a choreography.
  """

  use GenServer

  @type session_key :: term()
  @type session_state :: any()
  @type state :: %{
          pid_session: %{pid() => session_key()},
          # This is the shared state
          session_data: any(),
          session_handler: %{session_key() => pid()}
        }

  def init(init_state) do
    {:ok, %{pid_session: %{}, session_data: init_state, session_handler: %{}}}
  end

  def handle_call(
        {:begin_session, pids, backend, backend_func, backend_args},
        _caller,
        state
      ) do
    # could replace with a UUID
    session_key = :erlang.monotonic_time()
    {child, _child_ref} = spawn_monitor(backend, backend_func, backend_args)

    pids
    |> Enum.reduce(%{}, fn p, acc -> Map.put(acc, p, session_key) end)
    |> then(&Map.update!(state, :pid_session, fn old -> Map.merge(old, &1) end))
    |> put_in([:session_handler, session_key], child)
    |> then(&{:reply, :ok, &1})
  end

  def handle_call({:set_state, new_state}, _caller, state) do
    {:reply, :ok, %{state | session_data: new_state}}
  end

  # update_fn should return {ret_val, new_state}
  def handle_call(
        {:update_state, update_fn},
        _sender,
        state
      ) do
    {ret_val, new_state} = update_fn.(state[:session_data])
    {:reply, ret_val, %{state | session_data: new_state}}
  end

  def handle_call(:fetch_state, _sender, state) do
    {:reply, state[:session_data], state}
  end

  # Inject key :proxy into config for all proxied modules
  def handle_info({:chorex, sender, {:config, config}}, state) when is_pid(sender) do
    with {:ok, _key, session_handler} <- fetch_session(state, sender) do
      send(session_handler, {:config, Map.put(config, :proxy, self())})
    end

    {:noreply, state}
  end

  def handle_info({:chorex, sender, msg}, state) when is_pid(sender) do
    with {:ok, _key, session_handler} <- fetch_session(state, sender) do
      # Forward to proxy
      send(session_handler, msg)
    end

    {:noreply, state}
  end

  # TEMPORARY FIX: Swallow DOWN messages
  def handle_info({:DOWN, _, _, _, _}, state), do: {:noreply, state}

  # Fetch all session data for the associated PID
  @spec fetch_session(state(), pid()) :: {:ok, session_key(), pid()} | :error
  defp fetch_session(state, pid) do
    with {:ok, session_key} <- Map.fetch(state[:pid_session], pid),
         {:ok, handler} <- Map.fetch(state[:session_handler], session_key) do
      {:ok, session_key, handler}
    end
  end

  #
  # Public API
  #

  def set_state(proxy, new_state) do
    GenServer.call(proxy, {:set_state, new_state})
  end

  def begin_session(proxy, session_pids, proxy_module, start_func, start_args) do
    GenServer.call(
      proxy,
      {:begin_session, session_pids, proxy_module, start_func, start_args}
    )
  end

  @doc """
  Updates the session state for the current process.

  For use by proxied processes.
  """
  @spec update_state(map(), (session_state() -> {any(), session_state()})) :: any()
  def update_state(config, update_fn) do
    GenServer.call(config[:proxy], {:update_state, update_fn})
  end

  def fetch_state(config) do
    GenServer.call(config[:proxy], :fetch_state)
  end

  @doc """
  Send a message to a proxied service.

  Handles the wrapping of the message with the `{:chorex, self(), ...}`
  tuple so that the proxy knows which session to send the message on to.
  """
  @spec send_proxied(pid(), any()) :: any()
  def send_proxied(proxy_pid, msg) do
    send(proxy_pid, {:chorex, self(), msg})
  end
end

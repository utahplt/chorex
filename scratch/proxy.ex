defmodule Chorex.Proxy do
  @moduledoc """
  Proxy for singletons in a choreography.
  """

  use GenServer

  @type session_key :: term()
  @type session_state :: any()
  @type state :: %{
          # This is the shared state
          session_data: any(),
          session_handler: %{session_key() => pid()}
        }

  def init(init_state) do
    {:ok, %{session_data: init_state, session_handler: %{}}}
  end

  def handle_call(
        {:begin_session, session_token, backend, backend_func, backend_args},
        _caller,
        state
      ) do

    # Create a backend handler for this session and remember
    {child, _child_ref} = spawn_monitor(backend, backend_func, backend_args)
    new_state = put_in(state, [:session_handler, session_token], child)

    {:reply, :ok, new_state}
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
  def handle_info({:chorex, session_key, :meta, {:config, config}}, state) do
    with {:ok, session_handler} <- fetch_session(state, session_key) do
      send(session_handler, {:chorex, session_key, :meta, {:config, Map.put(config, :proxy, self())}})
    end

    {:noreply, state}
  end

  # Normal messages going to the proxy
  def handle_info({signal, session_key, _sender, _receiver, _msg} = msg, state)
    when signal in [:chorex, :choice] do
    with {:ok, session_handler} <- fetch_session(state, session_key) do
      # Forward to handler
      send(session_handler, msg)
    end

    {:noreply, state}
  end

  # TEMPORARY FIX: Swallow DOWN messages
  def handle_info({:DOWN, _, _, _, _}, state), do: {:noreply, state}

  # Fetch all session data for the associated session key
  @spec fetch_session(state(), binary) :: {:ok, pid()} | :error
  defp fetch_session(state, session_key) do
    with {:ok, handler} <- Map.fetch(state[:session_handler], session_key) do
      {:ok, handler}
    end
  end

  #
  # Public API
  #

  def set_state(proxy, new_state) do
    GenServer.call(proxy, {:set_state, new_state})
  end

  def begin_session(proxy, session_token, proxy_module, start_func, start_args) do
    GenServer.call(
      proxy,
      {:begin_session, session_token, proxy_module, start_func, start_args}
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
end

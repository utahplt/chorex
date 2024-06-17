defmodule Chorex.Proxy do
  @moduledoc """
  Proxy for singletons in a choreography.
  """

  use GenServer

  @type session_key :: term()
  @type session_state :: any()
  @type state :: %{
          pid_session: %{pid() => session_key()},
          session_data: %{session_key() => any()},
          session_handler: %{session_key() => pid()}
        }

  def init(_) do
    {:ok, %{pid_session: %{}, session_data: %{}, session_handler: %{}}}
  end

  def handle_call(
        {:begin_session, pids, initial_state, backend, backend_func, backend_args},
        _caller,
        state
      ) do
    session_key = :erlang.monotonic_time()
    {child, _child_ref} = spawn_monitor(backend, backend_func, backend_args)

    pids
    |> Enum.reduce(%{}, fn p, acc -> Map.put(acc, p, session_key) end)
    |> then(&Map.update!(state, :pid_session, fn old -> Map.merge(old, &1) end))
    |> put_in([:session_data, session_key], initial_state)
    |> put_in([:session_handler, session_key], child)
    |> then(&{:reply, :ok, &1})
  end

  def handle_call(
        {:update_session_state, update_fn},
        sender,
        state
      ) do
    with {:ok, session_key, session_state, _handler} <- fetch_session(state, sender) do
      new_session_state = update_fn.(session_state)
      new_state = put_in(state, [:session_data, session_key], new_session_state)
      {:reply, {:ok, new_session_state}, new_state}
    end

    {:reply, :error, state}
  end

  # Inject key :proxy into config for all proxied modules
  def handle_info({:chorex, sender, {:config, config}}, state) when is_pid(sender) do
    with {:ok, _key, _state, session_handler} <- fetch_session(state, sender) do
      send(session_handler, {:config, Map.put(config, :proxy, self())})
    end

    {:noreply, state}
  end

  def handle_info({:chorex, sender, msg}, state) when is_pid(sender) do
    with {:ok, _key, _session_state, session_handler} <- fetch_session(state, sender) do
      # Forward to proxy
      send(session_handler, msg)
    end

    {:noreply, state}
  end

  @spec fetch_session(state(), pid()) :: {:ok, session_key(), session_state(), pid()} | :error
  defp fetch_session(state, pid) do
    with {:ok, session_key} <- Map.fetch(state[:pid_session], pid),
         {:ok, session_state} <- Map.fetch(state[:session_data], session_key),
         {:ok, handler} <- Map.fetch(state[:session_handler], session_key) do
      {:ok, session_key, session_state, handler}
    end
  end

  #
  # Public API
  #

  def begin_session(proxy, session_pids, initial_state, proxy_module, start_func, start_args) do
    GenServer.call(proxy,
      {:begin_session, session_pids, initial_state, proxy_module, start_func, start_args})
  end
end

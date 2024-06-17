defmodule StoreProxy do
  use GenServer

  @type session_key :: term()
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

  def handle_info({:chorex, sender, msg}, state) when is_pid(sender) do
    with {:ok, session_key} <- Map.fetch(state[:pid_session], sender),
         {:ok, _session_state} <- Map.fetch(state[:session_data], session_key),
         {:ok, handler} <- Map.fetch(state[:session_handler], session_key) do
      # FIXME: how do I want to thread the shared resource through?
      send(handler, msg)
    end

    {:noreply, state}
  end
end

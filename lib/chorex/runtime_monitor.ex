defmodule Chorex.RuntimeMonitor do
  @moduledoc """
  GenServer that monitors all actors in a choreography and attempts to
  restart the system when something goes down.
  """

  use GenServer

  alias Chorex.RuntimeSupervisor

  @type state :: %{
          return_pid: pid(),
          supervisor: nil | pid(),
          session_token: nil | any(),
          actors: %{reference() => {atom(), pid()}},
          setup: %{atom() => {module(), init_args :: any()}}
        }

  @impl true
  def init(return_pid) do
    {:ok, %{return_pid: return_pid, session_token: nil, supervisor: nil, setup: %{}, actors: %{}}}
  end

  @impl true
  def handle_call(:startup, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:get_config, _from, state) do
    config = get_config_from_state(state)
    {:reply, config, state}
  end

  def handle_call({:start_session, _}, _, %{supervisor: s} = state)
      when not is_nil(s),
      do: {:reply, {:error, :session_started}, state}

  def handle_call({:start_session, token}, _from, state) do
    {:ok, supervisor} = RuntimeSupervisor.start_link(token)
    {:reply, supervisor, %{state | supervisor: supervisor, session_token: token}}
  end

  def handle_call({:start_child, actor, module}, _from, state) do
    {:ok, pid} =
      RuntimeSupervisor.start_child(
        state.supervisor,
        module,
        {actor, module, state.return_pid, state.session_token}
      )

    ref = Process.monitor(pid)

    dbg({:monitor, actor, pid, ref})

    state = update_in(state.actors, &Map.put(&1, ref, {actor, pid}))

    {:reply, pid, state}
  end

  @impl true
  def handle_cast({:kickoff, init_args}, state) do
    config = get_config_from_state(state)
    msg = {:config, config, init_args}

    for {_ref, {_a, pid}} <- state.actors do
      send(pid, msg)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    dbg({:got_DOWN, ref, pid, reason})
    # FIXME: send {:restarting, state.session_token, new_network, unwind_point} to all actors
    {:noreply, state}
  end

  #
  # API functions
  #

  def start_session(token) do
    {:ok, pid} = GenServer.start_link(__MODULE__, self())
    _supervisor = GenServer.call(pid, {:start_session, token})
    {:ok, pid}
  end

  def start_child(gs, actor, module) do
    child_pid = GenServer.call(gs, {:start_child, actor, module})
    {:ok, child_pid}
  end

  def kickoff(gs, init_args) do
    GenServer.cast(gs, {:kickoff, init_args})
  end

  #
  # Helper functions
  #

  def get_config_from_state(state) do
    for {_ref, {a, p}} <- state.actors do
      {a, p}
    end
    |> Enum.into(%{})
    |> Map.put(:session_token, state.session_token)
    |> Map.put(:super, state.return_pid)
  end
end

defmodule Chorex.RuntimeMonitor do
  @moduledoc """
  GenServer that monitors all actors in a choreography and attempts to
  restart the system when something goes down.
  """

  use GenServer

  alias Chorex.RuntimeSupervisor
  alias Chorex.RuntimeState

  @type unwind_point() :: String.t()

  @type state :: %{
          return_pid: pid(),
          supervisor: nil | pid(),
          session_token: nil | any(),
          actors: %{reference() => {atom(), pid()}},
          state_store: %{atom() => %{unwind_point() => RuntimeState.t()}},
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
    state = update_in(state.actors, &Map.put(&1, ref, {actor, pid}))

    {:reply, pid, state}
  end

  def handle_call({:start_remote, actor, spec}, _from, state) do
    {:remote, lport, rhost, rport} = spec

    {:ok, proxy_pid} =
      GenServer.start(
        Chorex.SocketProxy,
        %{listen_port: lport, remote_host: rhost, remote_port: rport}
      )

    ref = Process.monitor(proxy_pid)
    state = update_in(state.actors, &Map.put(&1, ref, {actor, proxy_pid}))

    {:reply, proxy_pid, state}
  end

  @impl true
  def handle_cast({:kickoff, init_args}, state) do
    config = get_config_from_state(state)
    msg = {:config, config, init_args}

    for {_ref, {_a, pid}} <- state.actors do
      # FIXME: I might need to NOT send this to proxied actors
      send(pid, msg)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, down_ref, :process, pid, reason}, state) do
    dbg({:got_DOWN, down_ref, pid, reason})

    state_ = revive(down_ref, state)
    network = get_config_from_state(state_)

    # FIXME: get the recovery token
    for {ref, {name, pid}} <- state_.actors, ref != down_ref do
      recover(name, pid, network)
    end

    {:noreply, state_}
  end

  #
  # API functions
  #

  def start_session(token) do
    {:ok, pid} = GenServer.start_link(__MODULE__, self())
    _supervisor = GenServer.call(pid, {:start_session, token})
    {:ok, pid}
  end

  def start_remote(gs, actor, {:remote, _, _, _} = spec) do
    child_pid = GenServer.call(gs, {:start_remote, actor, spec})
    {:ok, child_pid}
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

  @doc """
  Restore the actor that used to be at reference `ref`. Return the
  state with an updated network configuration.
  """
  def revive(ref, state) do
    dbg({:revive, ref})
    state
  end

  @doc """
  Tell actor `name` at `pid` to recover with new network `new_config`.

  Called for effect; no meaningful return value.
  """
  def recover(name, pid, new_config) do
    dbg({:recover, name, pid, new_config})
    :ok
  end

  def get_config_from_state(state) do
    for {_ref, {a, p}} <- state.actors do
      {a, p}
    end
    |> Enum.into(%{})
    |> Map.put(:session_token, state.session_token)
    |> Map.put(:super, state.return_pid)
  end
end

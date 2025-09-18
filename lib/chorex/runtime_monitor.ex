defmodule Chorex.RuntimeMonitor do
  @moduledoc """
  GenServer that monitors all actors in a choreography and attempts to
  restart the system when something goes down.
  """

  use GenServer

  alias Chorex.RuntimeSupervisor
  alias Chorex.RuntimeState

  import Utils, only: [assoc_put: 3, assoc_del: 2, assoc_get: 2]

  @profile_memory false

  @type unwind_point() :: String.t()
  @type sync_token() :: String.t()
  @type barrier_token() :: tuple()

  @type state :: %{
          return_pid: pid(),
          supervisor: nil | pid(),
          session_token: nil | any(),
          actors: %{reference() => {atom(), pid()}},
          state_store: %{atom() => [{barrier_token(), RuntimeState.t()}]},
          sync_barrier: %{sync_token() => %{atom() => boolean()}},
          setup: %{atom() => module()},
          _profile: any()       # internal; maybe leave out of typespec?
        }

  @impl true
  def init(return_pid) do
    {:ok,
     %{
       return_pid: return_pid,
       session_token: nil,
       supervisor: nil,
       setup: %{},
       actors: %{},
       state_store: %{},
       sync_barrier: %{},
       _profile: %{memory_hwm: 0}
     }}
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
    # See function revive/2
    {:ok, pid} =
      RuntimeSupervisor.start_child(
        state.supervisor,
        module,
        {actor, module, state.return_pid, state.session_token}
      )

    ref = Process.monitor(pid)
    state = update_in(state.actors, &Map.put(&1, ref, {actor, pid}))
    state = update_in(state.setup, &Map.put(&1, actor, module))

    {:reply, pid, state}
  end

  def handle_call({:start_remote, actor, spec}, _from, state) do
    {:remote, lport, rhost, rport} = spec

    {:ok, proxy_pid} =
      GenServer.start(
        Chorex.SocketProxy,
        %{
          listen_port: lport,
          remote_host: rhost,
          remote_port: rport,
          session_token: state.session_token
        }
      )

    ref = Process.monitor(proxy_pid)
    state = update_in(state.actors, &Map.put(&1, ref, {actor, proxy_pid}))

    {:reply, proxy_pid, state}
  end

  @impl true
  def handle_cast({:kickoff, init_args}, state) do
    config = get_config_from_state(state)
    msg = {:config, config, init_args}

    # FIXME: I might need to NOT send this to proxied actors
    send_to_all(msg, state)

    {:noreply, state}
  end

  def handle_cast({:save_state, actor, barrier_token, actor_state}, state) do
    # Don't store actor's mailbox
    actor_state = %{actor_state | inbox: :queue.new()}

    state_ =
      if Map.has_key?(state.state_store, actor),
        do: state,
        else: put_in(state.state_store[actor], [])

    state_ = update_in(state_.state_store[actor], &assoc_put(&1, barrier_token, actor_state))

    state_ =
      if @profile_memory do
        update_in(state_._profile.memory_hwm, & max(&1, :erlang.external_size(state_)))
      else
        state_
      end

    {:noreply, state_}
  end

  def handle_cast({:begin_checkpoint, sync_token}, state) do
    case Map.fetch(state.sync_barrier, sync_token) do
      {:ok, _map} ->
        # Already begun
        {:noreply, state}

      :error ->
        actor_map =
          for({_ref, {a, _pid}} <- state.actors, do: {a, false})
          |> Enum.into(%{})

        state_ = put_in(state.sync_barrier[sync_token], actor_map)
        {:noreply, state_}
    end
  end

  # Called when actor finishes block
  def handle_cast({:checkpoint, sync_token, actor}, state) do
    state_ = put_in(state.sync_barrier[sync_token][actor], true)
    {:noreply, state_, {:continue, {:try_lift_checkpoint, sync_token}}}
  end

  @impl true
  def handle_info({:DOWN, _down_ref, :process, _pid, :normal}, state) do
    # process terminated normally (end of choreography)

    ok_to_finish =
      state.actors
      |> Enum.map(fn {_, {_ref, pid}} -> pid end)
      |> Enum.map(&Process.alive?/1)
      |> Enum.all?(&(not &1))

    if ok_to_finish do
      if @profile_memory do
        IO.puts("\n[PROFILER] Monitor memory high-watermark: #{state._profile.memory_hwm} bytes\n")
      end

      {:stop, :normal, nil}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, down_ref, :process, _pid, _reason}, state) do
    # process crashed

    {state_, barrier_token} = revive(down_ref, state)
    network = get_config_from_state(state_)

    for {ref, {name, pid}} <- state_.actors, ref != down_ref do
      recover(name, pid, network, barrier_token, state_)
    end

    # Pop old states off state store
    new_state_store =
      for({actor, state_assoc_list} <- state_.state_store, do: {actor, assoc_del(state_assoc_list, barrier_token)})
      |> Enum.into(%{})

    {:noreply, %{state_ | state_store: new_state_store}}
  end

  @impl true
  def handle_continue({:try_lift_checkpoint, sync_token}, state) do
    ok_to_lift =
      state.sync_barrier[sync_token]
      |> Map.values()
      |> Enum.all?(& &1)

    if ok_to_lift do
      # sync_token looks like {:barrier, session_token, barrier_id, stack_depth}
      send_to_actors(Map.keys(state.sync_barrier[sync_token]), sync_token, state)

      # Pop old states off state store
      barrier_token = sync_token
      new_state_store =
        for({actor, state_assoc_list} <- state.state_store, do: {actor, assoc_del(state_assoc_list, barrier_token)})
        |> Enum.into(%{})

      # set locks to false
      fresh_locks =
        for({_ref, {a, _pid}} <- state.actors, do: {a, false})
        |> Enum.into(%{})

      new_sync_barrier =
        Map.put(state.sync_barrier, sync_token, fresh_locks)

      {:noreply, %{state | state_store: new_state_store, sync_barrier: new_sync_barrier}}
    else
      {:noreply, state}
    end
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

  def begin_checkpoint(gs, sync_token) do
    GenServer.cast(gs, {:begin_checkpoint, sync_token})
  end

  def end_checkpoint(gs, actor, sync_token) do
    GenServer.cast(gs, {:checkpoint, sync_token, actor})
  end

  def checkpoint_state(gs, actor, barrier_token, state) do
    GenServer.cast(gs, {:save_state, actor, barrier_token, state})
  end

  #
  # Helper functions
  #

  defp send_to_actors(actors, msg, state) do
    conf = get_config_from_state(state)

    for a <- actors do
      send(conf[a], msg)
    end
  end

  defp send_to_all(msg, state) do
    for {_ref, {_a, pid}} <- state.actors do
      send(pid, msg)
    end
  end

  @doc """
  Restore the actor that used to be at reference `ref`. Return the
  state with an updated network configuration.
  """
  def revive(ref, state) do
    {actor, _old_pid} = state.actors[ref]
    module = state.setup[actor]

    # See handle_call({:start_child, ...}, ...)
    {:ok, pid} =
      RuntimeSupervisor.start_child(
        state.supervisor,
        module,
        {actor, module, state.return_pid, state.session_token}
      )

    new_ref = Process.monitor(pid)
    state = update_in(state.actors, &Map.delete(&1, ref))
    state = update_in(state.actors, &Map.put(&1, new_ref, {actor, pid}))

    case state.state_store[actor] do
      [{b_tok, %{stack: [{:barrier, _, _, _} = b_tok | _]} = last_actor_state} | _] ->
        send(pid, {:revive, last_actor_state})
        {state, b_tok}

      [] ->
        raise RuntimeError, message: "Actor #{actor} crashed and no rescue available"
    end
  end

  @doc """
  Tell actor `name` at `pid` to recover with new network `new_config`.

  Called for effect; no meaningful return value.
  """
  def recover(name, pid, new_config, barrier_token, state) do
    case assoc_get(state.state_store[name], barrier_token) do
      {_, recover_state} ->
        send(pid, {:recover, state.session_token, new_config, barrier_token, recover_state.vars})

      nil ->
        # Sometimes no state has been saved yet; in this case, don't bother restoring variables
        send(pid, {:recover, state.session_token, new_config, barrier_token, nil})
    end
    :ok
  end

  def get_config_from_state(state) do
    for {_ref, {a, p}} <- state.actors do
      {a, p}
    end
    |> Enum.into(%{})
    |> Map.put(:monitor, self())
    |> Map.put(:session_token, state.session_token)
    |> Map.put(:super, state.return_pid)
  end
end

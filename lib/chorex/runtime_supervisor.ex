defmodule Chorex.RuntimeSupervisor do
  @moduledoc """
  DynamicSupervisor for Chorex actors.
  """

  @registry_name Chorex.Registry

  use DynamicSupervisor

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_link(session_token) do
    DynamicSupervisor.start_link(
      __MODULE__,
      [],
      name: {:via, Registry, {@registry_name, session_token}}
    )
  end

  def start_child(sup_name, mod_name, arg) do
    # restart is temporary; the RuntimeMonitor takes care of restarting crashed processes
    spec = %{id: mod_name, start: {GenServer, :start_link, [mod_name, arg]}, restart: :temporary}
    DynamicSupervisor.start_child(sup_name, spec)
  end
end

defmodule Chorex.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, name: Chorex.Registry, keys: :unique}
    ]
    Supervisor.start_link(children, name: Chorex.Supervisor, strategy: :one_for_one)
  end
end

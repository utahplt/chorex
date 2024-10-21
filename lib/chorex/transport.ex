defmodule Chorex.Transport do
  @moduledoc """
  Generalized message sending backend.
  """

  # Idea: generalize the message sending/receiving and have an API
  # that different backends can implement.

  use GenServer

  def init(_) do
    # HELP! I need queue semantics, not stack semantics!
    {:ok, %{inbox: [], outbox: []}}
  end

  def handle_call({{:send, msg}, _sender, %{outbox: ob} = state}) do
    send(self(), :process_outbox)
    {:reply, :ok, %{state | outbox: ob ++ [msg]}}
  end

  def handle_info(:process_outbox, %{outbox: []} = state),
    do: {:noreply, state}

  def handle_info(:process_outbox, %{outbox: ob} = state) do
    #  FIXME: send everything in `ob`
    {:noreply, %{state | outbox: []}}
  end
end

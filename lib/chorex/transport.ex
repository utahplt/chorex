defmodule Chorex.Transport do
  @moduledoc """
  Generalized message sending backend.
  """

  alias __MODULE__

  use GenServer

  @spec init(backend :: Transport.Backend.t()) :: {:ok, any()}
  def init(backend) do
    {:ok, %{backend: backend, inbox: :queue.new(), outbox: :queue.new()}}
  end

  def handle_call({{:send, msg}, _sender, %{outbox: ob} = state}) do
    send(self(), :process_outbox)
    {:reply, :ok, %{state | outbox: :queue.snoc(ob, msg)}}
  end

  def handle_info(:process_outbox, %{backend: backend, outbox: ob} = state) do
    leftovers = Transport.Backend.send_msg(backend, :queue.to_list(ob))
    {:noreply, %{state | outbox: :queue.from_list(leftovers)}}
  end
end

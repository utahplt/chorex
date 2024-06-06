defmodule BookServer do
  use GenServer

  # The maxim: a new function every time you receive a value.
  # We will need a "local vars" map in the state.

  def init(_), do: {:ok, _}

  def handle_cast({:chorex_register_session, token, config}, _from, state) do
	{:noreply, Map.put(state, token, {config, %{step: :start}})}
  end

  def handle_cast({:chorex_message, session_token, message}, _from, state) do
    {session_config, session_state} = state[session_token] # TODO: handle bad session tokens? Or is that too defensive?

    chorex_dispatch(session_state[:step], message, session_state, session_config)
    |> &{:noreply, Map.put(state, session_token, &{session_config, &1})}
  end

  # chorex_dispatch gets view of system from a single session's point of view
  def chorex_dispatch(:start, message, state, config) do
    %{state | step: :await_book}
  end

  def chorex_dispatch(:await_book, message, state, config) do
    state = Map.put(state, :book_title, message)
    # FIXME: have special functions to wrap calling with session token etc.
    GenServer.cast(config[Buyer], get_book_price(state[:book_title]))

    %{state | step: :await_decision}
  end

  def get_book_price(title) do
    prices = %{
      "Das Glasperlenspiel" => 42,
      "The Count of Monte Cristo" => 17,
      "Zen and the Art of Motorcycle Maintenance" => 16,
      "Anathem" => 12
    }

    Map.get(prices, title, 0)
  end
end

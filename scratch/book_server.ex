defmodule BookServer do
  use GenServer

  # The maxim: a new function every time you receive a value.
  # We will need a "local vars" map in the state.

  @type session_config() :: %{atom() => pid()}
  @type machine_state() :: atom()
  @type local_vars() :: %{atom => any()}
  @type session_state_bundle() :: {session_config(), machine_state(), local_vars()}

  def init(_), do: {:ok, _}

  def handle_cast({:chorex_register_session, token, config}, _from, state) do
    # state bundle: {session_network_config, machine state, local vars}
    {:noreply, Map.put(state, token, {config, :start, %{}})}
  end

  def handle_cast({:chorex_message, session_token, message}, _from, state) do
    # TODO: handle bad session tokens? Or is that too defensive?
    {session_config, machine_state, local_vars} = state[session_token]

    {next_machine_state, next_local_vars} =
      chorex_dispatch(machine_state, message, session_config, local_vars, session_token)

    {:noreply, {session_config, next_machine_state, next_local_vars}}
  end

  # Utility function
  def chorex_send(dest, config, token, message) do
    GenServer.cast(config[dest], {:chorex_message, token, message})
  end

  # chorex_dispatch gets view of system from a single session's point of view
  @spec chorex_dispatch(machine_state(), term(), session_config(), local_vars(), session_token()) ::
          {machine_state(), local_vars()}
  def chorex_dispatch(:start, _message, _config, vars, _token) do
    {:await_book, vars}
  end

  def chorex_dispatch(:await_book, message, config, vars, token) do
    vars = Map.put(vars, :book_title, message)
    chorex_send(Buyer, config, token, get_book_price(vars[:book_title]))

    {:await_decision, vars}
  end

  # Buy the book
  def chorex_dispatch(:await_decision, L, config, vars, token) do
    date = shipping_date(vars[:book_title])
    chorex_send(Buyer, config, token, date)
  end

  # No buy
  def chorex_dispatch(:await_decision, R, config, vars, token) do
    chorex_send(:super, config, token, nil)
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

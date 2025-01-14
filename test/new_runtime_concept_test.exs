defmodule NewRuntimeConceptTest do
  use ExUnit.Case

  # Alice.one() ~> Bob.(x)
  # Alice.two() ~> Bob.(y)
  # Bob.(x + y)

  defmodule Alice do
    use Chorex.Runtime
  end

  defmodule Bob do
    use Chorex.Runtime

    def run(state) do
      new_state = push_recv_frame({{state.session_tok, :first, Alice, Bob},
                                   :x, "getting_x", %{}}, state)
      continue_on_stack(nil, dbg(new_state))
    end

    def handle_continue({"getting_x", vars, x}, state) do
      new_state = push_recv_frame({{state.session_tok, :second, Alice, Bob},
                                   :y, "getting_y", %{x: x}}, state)
      continue_on_stack(nil, dbg(new_state))
    end

    def handle_continue({"getting_y", vars, y}, state) do
      dbg()
      continue_on_stack({vars[:x], y}, state)
    end
  end

  defmodule MyAliceImpl do
    import Chorex.Runtime
    def one(), do: 40
    def two(), do: 2

    def run(state) do
      config = state[:config]
      impl = state[:impl]

      chorex_send(Alice, Bob, :first, impl.one())
      chorex_send(Alice, Bob, :second, impl.two())
      {:noreply, state}
    end
  end

  defmodule MyBobImpl do
    import Chorex.Runtime
    def run(state) do
      {:noreply, push_recv_frame({{state.session_tok, :first, Alice, Bob},
                                  :x, "getting_x", %{}}, state)}
    end
  end

  test "actors turn on" do
    # tok = UUID.uuid4()
    tok = "test_static"

    {:ok, alice_pid} = GenServer.start_link(Alice, {Alice, MyAliceImpl, self(), tok})
    {:ok, bob_pid} = GenServer.start_link(Bob, {Bob, MyBobImpl, self(), tok})

    config = %{Alice => alice_pid, Bob => bob_pid}
    dbg(config)
    send(alice_pid, {:config, config})
    send(bob_pid, {:config, config})

    assert_receive {:chorex_return, Bob, {40, 2}}, 500
  end
end

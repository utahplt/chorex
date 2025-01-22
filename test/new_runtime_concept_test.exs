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

    def handle_continue({"getting_x", _vars, x}, state) do
      new_state = push_recv_frame({{state.session_tok, :second, Alice, Bob},
                                   :y, "getting_y", %{x: x}}, state)
      continue_on_stack(nil, new_state)
    end

    def handle_continue({"getting_y", vars, y}, state) do
      continue_on_stack({vars[:x], y}, state)
    end
  end

  defmodule MyAliceImpl do
    use Chorex.Runtime
    def one(), do: 40
    def two(), do: 2

    def run(state) do
      config = state.config
      impl = state.impl

      chorex_send(Alice, Bob, :first, impl.one())
      chorex_send(Alice, Bob, :second, impl.two())
      {:noreply, state}
    end
  end

  defmodule MyBobImpl do
    use Chorex.Runtime
    def run(state) do
      {:noreply, push_recv_frame({{state.session_tok, :first, Alice, Bob},
                                  :x, "getting_x", %{}}, state)}
    end
  end

  @tag :skip
  test "actors turn on and send messages" do
    # tok = UUID.uuid4()
    tok = "test_static"

    {:ok, alice_pid} = GenServer.start_link(Alice, {Alice, MyAliceImpl, self(), tok})
    {:ok, bob_pid} = GenServer.start_link(Bob, {Bob, MyBobImpl, self(), tok})

    config = %{Alice => alice_pid, Bob => bob_pid}
    send(alice_pid, {:config, config})
    send(bob_pid, {:config, config})

    assert_receive {:chorex_return, Bob, {40, 2}}, 500
  end

  # Alice.one() ~> Bob.(x)
  # with Bob.(z) <- compute(Bob.(x)) do
  #   Alice.two() ~> Bob.(y)
  #   Bob.({x, y, z})
  # end
  #
  # def compute(Bob.(a)) do     # computes 2a+2
  #   Bob.(a + 1) ~> Alice.(b)
  #   Alice.(b + 1) ~> Bob.(c)
  #   Bob.(c + a)
  # end

  # Alice projection:
  #
  # one() -> Bob
  # compute()
  #   recv(b)
  #   b+1 -> Bob
  # two() -> Bob

  # Bob projection:
  #
  # recv(x)           ; 40
  # compute(a: x)
  #   a+1 -> Alice    ; 41 -> Alice
  #   recv(c)         ; 42
  #   ret(c + a) : z  ; 82
  # recv(y)           ; 2
  # {x, y, z}

  defmodule Alice2 do
    use Chorex.Runtime

    def compute(_, state) do
      new_state = push_recv_frame({{state.session_tok, :cmp1, NewRuntimeConceptTest.Bob2, Alice2}, :b, "getting_b", %{}}, state)
      continue_on_stack(nil, new_state)
    end

    def handle_continue({"getting_b", _vars, b}, state) do
      config = state.config
      # impl = state.impl
      chorex_send(Alice2, NewRuntimeConceptTest.Bob2, :cmp2, b + 1)
      continue_on_stack(nil, state)
    end

    def handle_continue({"comp_ret", _}, state) do
      config = state.config
      impl = state.impl

      chorex_send(Alice2, NewRuntimeConceptTest.Bob2, :w1, impl.two())
      continue_on_stack(nil, state)
    end
  end

  defmodule Bob2 do
    use Chorex.Runtime

    def handle_continue({"getting_x", _vars, x}, state) do
      new_state = push_func_frame({"comp_ret", put_var(state, :x, x).vars}, state)
      compute(x, new_state)
    end

    def handle_continue({"getting_c", vars, c}, state) do
      # config = state.config
      # impl = state.impl
      continue_on_stack(c + vars[:a], state)
    end

    def handle_continue({"comp_ret", z}, state) do
      state_ = put_var(state, :z, z)

      new_state =
        push_recv_frame({{state.session_tok, :w1, Alice2, Bob2}, :y, "getting_y", state_.vars}, state_)
      continue_on_stack(nil, new_state)
    end

    def handle_continue({"getting_y", vars, y}, state) do
      continue_on_stack({vars[:x], y, vars[:z]}, state)
    end

    def compute(a, state) do
      config = state.config
      # impl = state.impl

      chorex_send(Bob2, Alice2, :cmp1, a + 1)
      new_state = push_recv_frame({{state.session_tok, :cmp2, Alice2, Bob2}, :c, "getting_c", %{a: a}}, state)
      continue_on_stack(nil, new_state)
    end
  end

  defmodule MyAlice2Impl do
    use Chorex.Runtime

    def one(), do: 40
    def two(), do: 2

    def run(state) do
      config = state.config
      impl = state.impl

      chorex_send(Alice2, Bob2, :first, impl.one())

      # This is what a function call looks like: set up the return, then call.
      #
      # In practice, `compute` would be in the right namespace for a bare call I believe.
      new_state = push_func_frame({"comp_ret", state.vars}, state)
      Alice2.compute(nil, new_state)
    end
  end

  defmodule MyBob2Impl do
    use Chorex.Runtime

    def run(state) do
      new_state =
        push_recv_frame({{state.session_tok, :first, Alice2, Bob2}, :x, "getting_x", %{}}, state)

      {:noreply, new_state}
    end
  end

  @tag :skip
  test "more complex with a function call" do
    tok = "test_static2"

    {:ok, alice_pid} = GenServer.start_link(Alice2, {Alice2, MyAlice2Impl, self(), tok})
    {:ok, bob_pid} = GenServer.start_link(Bob2, {Bob2, MyBob2Impl, self(), tok})

    config = %{Alice2 => alice_pid, Bob2 => bob_pid}
    send(alice_pid, {:config, config})
    send(bob_pid, {:config, config})

    assert_receive {:chorex_return, Bob2, {40, 2, 82}}, 500
  end
end

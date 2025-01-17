defmodule ChorexTest do
  use ExUnit.Case
  import Chorex

  # quote do
  #   defchor [Alice, Bob] do
  #     def run() do
  #       Alice.one() ~> Bob.(x)
  #       Alice.two() ~> Bob.(y)
  #       Bob.(x + y)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule MiniTestChor do

    alias Chorex.Runtime

    defmodule Chorex do
      def get_actors() do
        [Alice, Bob]
      end

      (
        def alice do
          quote do
            import Alice
            @behaviour Alice
            import Runtime
            nil
            defdelegate handle_continue(a, b), to: Alice
          end
        end

        defmodule Alice do
          use Runtime
          @callback one() :: any()
          @callback two() :: any()
          def run(state) do
            ret = nil
            config = state[:config]
            impl = state[:impl]
            :sender_sending
            civ_tok = {config[:session_token], [], Alice, Bob}
            send(config[Bob], {:chorex, {state.session_tok, civ_tok, Alice, Bob}, impl.one()})
            :sender_sending
            civ_tok = {config[:session_token], [], Alice, Bob}
            send(config[Bob], {:chorex, {state.session_tok, civ_tok, Alice, Bob}, impl.two()})
            :here_return
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            continue_on_stack(ret, state)
          end
        end
      )

      (
        def bob do
          quote do
            import Bob
            nil
            import Runtime
            nil
            defdelegate handle_continue(a, b), to: Bob
          end
        end

        defmodule Bob do
          use Runtime

          def handle_continue({"4e0019dd-baf5-423a-85ba-758ffd610335", vars, y}, state) do
            ret = x + y
            :need_to_return
            :here_return
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            continue_on_stack(ret, state)
          end

          def handle_continue({"f39a7022-9e25-42ae-9146-0e1ce61b4afd", vars, x}, state) do
            :receiver_receiving
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            civ_tok = {config[:session_token], [], Alice, Bob}

            state =
              push_recv_frame({civ_tok, y, "4e0019dd-baf5-423a-85ba-758ffd610335", state.vars}, state)

            continue_on_stack(nil, state)
          end

          def run(state) do
            ret = nil
            config = state[:config]
            impl = state[:impl]
            :receiver_receiving
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            civ_tok = {config[:session_token], [], Alice, Bob}

            state =
              push_recv_frame({civ_tok, x, "f39a7022-9e25-42ae-9146-0e1ce61b4afd", state.vars}, state)

            continue_on_stack(nil, state)
          end
        end
      )

      defmacro __using__(which) do
        apply(__MODULE__, which, [])
      end
    end
    # defchor [Alice, Bob] do
    #   def run() do
    #     Alice.one() ~> Bob.(x)
    #     Alice.two() ~> Bob.(y)
    #     Bob.(x + y)
    #   end
    # end
  end

  defmodule MyAlice do
    use MiniTestChor, :alice

    def one(), do: 40
    def two(), do: 2
  end

  defmodule MyBob do
    use MiniTestChor, :bob
  end

  test "smallest choreography test" do
    Chorex.start(MiniTestChor.Chorex, %{Alice => MyAlice, Bob => MyBob}, [])
    assert_receive({:chorex_return, Bob, 42})
  end
end

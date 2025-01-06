defmodule OooTmpTest do
  use ExUnit.Case

  defmodule Ooo do
    defmodule Chorex do
      def get_actors() do
        [Alice, Bob]
      end

      def alice do
        quote do
          alias OooTmpTest.Ooo.Chorex.Alice
          alias OooTmpTest.Ooo.Chorex.Bob
          import Alice
          @behaviour Alice
          use GenServer
          defdelegate handle_continue(a, b), to: Alice

          def init({parent_pid, args}) do
            Alice.init(__MODULE__, parent_pid, args)
          end
        end
      end

      defmodule Alice do
        @callback one() :: any()
        @callback two() :: any()
        def init(impl, parent_pid, args) do
          state = %{
            impl: impl,
            vars: %{},
            config: nil,
            stack: [finish_choreography: %{return_pid: parent_pid}]
          }

          {:ok, state, {:continue, {:startup, args}}}
        end

        def handle_continue({:startup, args}, state) do
          receive do
            {:chorex, _session_token, :meta, {:config, config}} ->
              apply(__MODULE__, :run, args ++ [%{state | config: config}])
          end
        end

        def handle_continue({:finish_choreography, ret}, state) do
          send(state.vars.return_pid, {:chorex_return, Alice, ret})
          {:stop, :normal, state}
        end

        def run(state) do
          ret = nil
          config = state[:config]
          impl = state[:impl]
          :deferring_to_body

          (
            tok = config[:session_token]
            # Tweak the order of these sends
            [first, second] = impl.get_ordering()
            send(config[Bob], {:chorex, tok, first, Alice, Bob, impl.two()})
            send(config[Bob], {:chorex, tok, second, Alice, Bob, impl.one()})
            :here_return
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            :making_continue
            [{tok, vars} | rest_stack] = state.stack
            {:noreply, %{state | vars: vars, stack: rest_stack}, {:continue, {tok, ret}}}
          )
        end
      end

      def bob do
        quote do
          alias OooTmpTest.Ooo.Chorex.Bob
          alias OooTmpTest.Ooo.Chorex.Alice
          import Bob
          nil
          use GenServer
          defdelegate handle_info(a, b), to: Bob
          defdelegate handle_continue(a, b), to: Bob

          def init({parent_pid, args}) do
            Bob.init(__MODULE__, parent_pid, args)
          end
        end
      end

      defmodule Bob do
        def init(impl, parent_pid, args) do
          state = %{
            impl: impl,
            vars: %{},
            config: nil,
            stack: [finish_choreography: %{return_pid: parent_pid}]
          }

          {:ok, state, {:continue, {:startup, args}}}
        end

        def handle_continue({:startup, args}, state) do
          receive do
            {:chorex, _session_token, :meta, {:config, config}} ->
              apply(__MODULE__, :run, args ++ [%{state | config: config}])
          end
        end

        def handle_continue({:finish_choreography, ret}, state) do
          send(state.vars.return_pid, {:chorex_return, Bob, ret})
          {:stop, :normal, state}
        end

        def handle_continue({:all_messages, nil}, state) do
          x = state.vars[:x]
          y = state.vars[:y]
          config = state[:config]
          impl = state[:impl]

          ret = x + y
          :need_to_return
          :here_return
          state = put_in(state.vars[:y], y)
          state = put_in(state.vars[:x], x)
          state = put_in(state[:config], config)
          state = put_in(state[:impl], impl)
          :making_continue
          [{tok, vars} | rest_stack] = state.stack
          {:noreply, %{state | vars: vars, stack: rest_stack}, {:continue, {tok, ret}}}
        end

        def handle_info({:chorex, tok, 2, _, _, msg}, state)
            when state.config.session_token == tok do
          ret = nil
          x = state.vars[:x]
          y = msg

          # check if got all variables
          if x && y do
            dbg({x, y})
            :making_continue
            state = put_in(state.vars[:y], y)
            [{tok, vars} | rest_stack] = state.stack
            vars = put_in(vars[:y], y)
            {:noreply, %{state | vars: vars, stack: rest_stack}, {:continue, {tok, ret}}}
          else
            dbg({x, y})
            # wait for it
            state = put_in(state.vars[:y], y)
            {:noreply, %{state | stack: [{:all_messages, state.vars} | state.stack]}}
          end
        end

        def handle_info({:chorex, tok, 1, _, _, msg}, state)
            when state.config.session_token == tok do
          ret = nil
          y = state.vars[:y]
          x = msg

          (
            :going_to_receive_see_handle_info

            # check if got all variables
            if x && y do
              dbg({x, y})
              :making_continue
              state = put_in(state.vars[:x], x)
              [{tok, vars} | rest_stack] = state.stack
              vars = put_in(vars[:x], x)
              {:noreply, %{state | vars: vars, stack: rest_stack}, {:continue, {tok, ret}}}
            else
              dbg({x, y})
              # wait for it
              state = put_in(state.vars[:x], x)
              {:noreply, %{state | stack: [{:all_messages, state.vars} | state.stack]}}
            end
          )
        end

        def handle_info(msg, state) do
          dbg(state)
          dbg(msg)
          {:noreply, state}
        end

        def run(state) do
          config = state[:config]
          impl = state[:impl]
          :deferring_to_body

          (
            :going_to_receive_see_handle_info
            state = put_in(state[:config], config)
            state = put_in(state[:impl], impl)
            {:noreply, state}
          )
        end
      end

      defmacro __using__(which) do
        apply(__MODULE__, which, [])
      end
    end
  end

  defmodule MyAlice do
    use Ooo.Chorex, :alice

    def one(), do: 1
    def two(), do: 2
    # def get_ordering(), do: [1, 2]
    def get_ordering(), do: [2, 1]
  end

  defmodule MyBob do
    use Ooo.Chorex, :bob
  end

  test "eh" do
    Chorex.start(
      Ooo.Chorex,
      %{
        Alice => MyAlice,
        Bob => MyBob
      },
      []
    )

    assert_receive {:chorex_return, OooTmpTest.Ooo.Chorex.Bob, 3}
  end
end

defmodule FunctionTest do
  use ExUnit.Case
  import Chorex

  # Check that we can compile a recursive choreography

  test "0-arity function compiles" do
    expanded =
      quote do
        defchor [Handler, Client] do
          def loop() do
            with Handler.(resp) <- Handler.run() do
              if Handler.continue?(resp) do
                Handler[L] ~> Client
                Handler.fmt_reply(resp) ~> Client.(resp)
                Client.send(resp)
                loop()
              else
                Handler[R] ~> Client
                Handler.fmt_reply(resp) ~> Client.(resp)
                Client.send(resp)
              end
            end
          end

          def run() do
            loop()
          end
        end
      end
      |> Macro.expand_once(__ENV__)

    # did we get something?
    assert {_, _, _} = expanded
  end

  defmodule CounterTest do
    defchor [CounterServer, CounterClient] do
      def loop(CounterServer.(i)) do
        if CounterClient.continue?() do
          CounterClient[L] ~> CounterServer
          CounterClient.bump() ~> CounterServer.(incr_amt)
          loop(CounterServer.(incr_amt + i))
        else
          CounterClient[R] ~> CounterServer
          CounterServer.(i) ~> CounterClient.(final_result)
          CounterClient.(final_result)
        end
      end

      def run() do
        loop(CounterServer.(0))
      end
    end
  end

  defmodule MyCounterServer do
    use CounterTest.Chorex, :counterserver
  end

  defmodule MyCounterClient do
    use CounterTest.Chorex, :counterclient

    def continue?() do
      # Process dictionary black magic!! Do not do! Testing only! Only
      # used to model getting value to continue from external source!
      Process.put(:acc, 1 + Process.get(:acc, 0))
      10 >= Process.get(:acc)
    end

    def bump(), do: Process.get(:acc)
  end

  test "looping increment test" do
    cs = spawn(MyCounterServer, :init, [[]])
    cc = spawn(MyCounterClient, :init, [[]])

    config = %{CounterServer => cs, CounterClient => cc, :super => self()}

    send(cs, {:config, config})
    send(cc, {:config, config})

    assert_receive {:chorex_return, CounterClient, 55}
  end
end

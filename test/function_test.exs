defmodule FunctionTest do
  use ExUnit.Case
  import Chorex

  # Check that we can compile a recursive choreography

  test "0-arity function compiles" do
    expanded =
      quote do
        defchor [Handler, Client] do
          def loop() do
            with Handler.(resp) <- Handler.do_run() do
              if Handler.continue?(resp) do
                Handler.fmt_reply(resp) ~> Client.(resp)
                Client.send(resp)
                loop()
              else
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
      # |> Macro.to_string()
      # |> IO.puts()

    # did we get something?
    assert {_, _, _} = expanded
  end

  defmodule CounterTest do
    defchor [CounterServer, CounterClient] do
      def loop(CounterServer.(i)) do
        if CounterClient.continue?() do
          CounterClient.bump() ~> CounterServer.(incr_amt)
          loop(CounterServer.(incr_amt + i))
        else
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

    @impl true
    def continue?() do
      # Process dictionary black magic!! Do not do! Testing only! Only
      # used to model getting value to continue from external source!
      Process.put(:acc, 1 + Process.get(:acc, 0))
      10 >= Process.get(:acc)
    end

    @impl true
    def bump(), do: Process.get(:acc)
  end

  test "looping increment test" do
    Chorex.start(
      CounterTest.Chorex,
      %{CounterServer => MyCounterServer, CounterClient => MyCounterClient},
      []
    )

    assert_receive {:chorex_return, CounterClient, 55}
  end

  defmodule ManyFuncsTest do
    defchor [ManyFuncsServer, ManyFuncsClient] do
      def f1(ManyFuncsClient.(x1)) do
        ManyFuncsClient.(x1 + 1) ~> ManyFuncsServer.(v1)
        with ManyFuncsServer.(v2) <- f2(ManyFuncsServer.(2 * v1), ManyFuncsClient.(x1)) do
          ManyFuncsServer.({v1, v2})
          ManyFuncsClient.(x1)
        end
      end

      def f2(ManyFuncsServer.(x2), ManyFuncsClient.(x2)) do
        ManyFuncsClient.(x2 + 7) ~> ManyFuncsServer.(v1)
        ManyFuncsServer.(v1 * 3)
      end

      def run() do
        ManyFuncsServer.i1() ~> ManyFuncsClient.(v1)
        f1(ManyFuncsClient.(v1))
      end
    end
  end

  defmodule MyFuncsClient do
    use ManyFuncsTest.Chorex, :manyfuncsclient
  end

  defmodule MyFuncsServer do
    use ManyFuncsTest.Chorex, :manyfuncsserver

    @impl true
    def i1(), do: 5
  end

  test "multiple functions (some not in tail-position) work" do
    Chorex.start(ManyFuncsTest.Chorex,
                 %{ManyFuncsServer => MyFuncsServer,
                 ManyFuncsClient => MyFuncsClient}, [])

    assert_receive {:chorex_return, ManyFuncsServer, {6, 36}}
    assert_receive {:chorex_return, ManyFuncsClient, 5}
  end

  #
  # Complex state
  #

  defmodule Counter2Test do
    defchor [Counter2Server, Counter2Client] do
      def loop(Counter2Server.(%{count: i})) do
        if Counter2Client.continue?() do
          Counter2Client.bump() ~> Counter2Server.(incr_amt)
          loop(Counter2Server.(%{count: incr_amt + i}))
        else
          Counter2Server.(i) ~> Counter2Client.(final_result)
          Counter2Client.(final_result)
        end
      end

      def run() do
        loop(Counter2Server.(%{count: 0}))
      end

      def run(Counter2Server.(start)) do
        loop(Counter2Server.(%{count: start}))
      end
    end
  end

  defmodule MyCounter2Server do
    use Counter2Test.Chorex, :counter2server
  end

  defmodule MyCounter2Client do
    use Counter2Test.Chorex, :counter2client

    @impl true
    def continue?() do
      # Process dictionary black magic!! Do not do! Testing only! Only
      # used to model getting value to continue from external source!
      Process.put(:acc, 1 + Process.get(:acc, 0))
      10 >= Process.get(:acc)
    end

    @impl true
    def bump(), do: Process.get(:acc)
  end

  test "looping increment with rich state" do
    Chorex.start(
      Counter2Test.Chorex,
      %{Counter2Server => MyCounter2Server, Counter2Client => MyCounter2Client},
      []
    )

    assert_receive {:chorex_return, Counter2Client, 55}

    Chorex.start(
      Counter2Test.Chorex,
      %{Counter2Server => MyCounter2Server, Counter2Client => MyCounter2Client},
      [100]
    )

    assert_receive {:chorex_return, Counter2Client, 155}
  end
end

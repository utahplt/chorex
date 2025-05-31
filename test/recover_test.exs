defmodule RecoverTest do
  use ExUnit.Case
  import Chorex

  # quote do
  #   defchor [RecAlice, RecBob] do
  #     def run(RecAlice.(param)) do
  #       RecAlice.one() ~> RecBob.(x)
  #       RecBob.two() ~> RecAlice.(a)
  #       try do
  #         RecAlice.two(a, param) ~> RecBob.(y)
  #         RecBob.(x + y)
  #       rescue
  #         RecAlice.(99)
  #         RecBob.(99)
  #       end
  #       # FIXME: write a program with a non-tail-position try/rescue
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule RecoverTestChor do
    defchor [RecAlice, RecBob] do
      def run(RecAlice.(param)) do
        RecAlice.one() ~> RecBob.(x)
        RecBob.two() ~> RecAlice.(a)
        try do
          RecAlice.two(a, param) ~> RecBob.(y)
          RecBob.(x + y)
        rescue
          RecAlice.(99) ~> RecBob.(rec_msg)
          RecBob.(98) ~> RecAlice.(rec_msg)
          RecAlice.(rec_msg)
          RecBob.(rec_msg)
        end
      end
    end
  end

  defmodule MyRecAlice do
    use RecoverTestChor.Chorex, :recalice

    @impl true
    def one(), do: 1

    @impl true
    def two(a, b) do
      a / (b - 1)
    end
  end

  defmodule MyRecBob do
    use RecoverTestChor.Chorex, :recbob

    @impl true
    def two(), do: 2
  end

  test "small happy-path try/rescue choreography" do
    Chorex.start(RecoverTestChor.Chorex, %{RecAlice => MyRecAlice, RecBob => MyRecBob}, [2])
    assert_receive {:chorex_return, RecBob, 3.0}, 500
  end

  test "small rescue-path try/rescue choreography" do
    Logger.configure(level: :none) # suppress crash messages
    Chorex.start(RecoverTestChor.Chorex, %{RecAlice => MyRecAlice, RecBob => MyRecBob}, [1])
    assert_receive({:chorex_return, RecAlice, 98}, 1_000)
    assert_receive({:chorex_return, RecBob, 99}, 1_000)
    Logger.configure(level: :warning) # restore
  end

  defmodule Recover2TestChor do
    defchor [Rec2Alice, Rec2Bob] do
      def run(Rec2Alice.(param), Rec2Alice.(logger), Rec2Bob.(logger)) do
        Rec2Alice.one() ~> Rec2Bob.(x)
        Rec2Bob.two() ~> Rec2Alice.(a)
        try do
          Rec2Alice.two(a, param) ~> Rec2Bob.(y)
          Rec2Bob.log_happy(logger, x + y)
        rescue
          Rec2Alice.log_failure(logger)
          Rec2Bob.log_failure(logger)
        end
        Rec2Alice.(1)
        Rec2Bob.(2)
      end
    end
  end

  defmodule MyRec2Alice do
    use Recover2TestChor.Chorex, :rec2alice

    @impl true
    def one(), do: 1

    @impl true
    def two(a, b) do
      a / (b - 1)
    end

    @impl true
    def log_failure(logger) do
      send(logger, {:log, :failed})
    end
  end

  defmodule MyRec2Bob do
    use Recover2TestChor.Chorex, :rec2bob

    @impl true
    def two(), do: 2

    @impl true
    def log_failure(logger) do
      send(logger, {:log, :failed})
    end

    @impl true
    def log_happy(logger, msg) do
      send(logger, {:log, {:happy, msg}})
    end
  end

  defmodule HandyLogger do
    use GenServer

    @impl true
    def init(_) do
      {:ok, []}
    end

    @impl true
    def handle_info({:log, msg}, state) do
	  {:noreply, [msg | state]}
    end

    @impl true
    def handle_call(:flush, _from, state) do
	  {:reply, state, []}
    end
  end

  test "happy-path with continuation" do
    {:ok, l1} = GenServer.start(HandyLogger, nil)
    {:ok, l2} = GenServer.start(HandyLogger, nil)

    Chorex.start(Recover2TestChor.Chorex, %{Rec2Alice => MyRec2Alice, Rec2Bob => MyRec2Bob}, [2, l1, l2])

    assert_receive {:chorex_return, Rec2Bob, 2}
    assert [] = GenServer.call(l1, :flush)
    assert [{:happy, 3.0}] = GenServer.call(l2, :flush)
  end

  test "failure-path with continuation" do
    {:ok, l1} = GenServer.start(HandyLogger, nil)
    {:ok, l2} = GenServer.start(HandyLogger, nil)

    Logger.configure(level: :none) # suppress crash messages
    # Note: parameter different
    Chorex.start(Recover2TestChor.Chorex, %{Rec2Alice => MyRec2Alice, Rec2Bob => MyRec2Bob}, [1, l1, l2])

    assert_receive {:chorex_return, Rec2Bob, 2}
    assert_receive {:chorex_return, Rec2Alice, 1}
    assert [:failed] = GenServer.call(l1, :flush)
    assert [:failed] = GenServer.call(l2, :flush)
    Logger.configure(level: :all)
  end
end

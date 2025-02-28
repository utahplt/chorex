defmodule BrokenRecoverTest do
  use ExUnit.Case

  import Chorex

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

  defmodule Recover3TestChor do
    defchor [Rec3Alice, Rec3Bob] do
      def run(Rec3Alice.(lgr), Rec3Bob.(lgr)) do
        try do
          Rec3Alice.f(1 / 0) ~> Rec3Bob.(y)
        rescue
          Rec3Alice.log_failure(lgr)
          Rec3Bob.log_failure(lgr)
        end
        Rec3Alice.(2 + 2) ~> Rec3Bob.(sum)
        Rec3Bob.(sum)
      end
    end
  end

  defmodule MyRec3Alice do
    use Recover3TestChor.Chorex, :rec3alice

    @impl true
    def f(a) do
      a
    end

    @impl true
    def log_failure(logger) do
      send(logger, {:log, :failed})
    end
  end

  defmodule MyRec3Bob do
    use Recover3TestChor.Chorex, :rec3bob

    @impl true
    def log_failure(logger) do
      send(logger, {:log, :failed})
    end
  end

  test "failure-path2 with continuation" do
    {:ok, l1} = GenServer.start(HandyLogger, nil)
    {:ok, l2} = GenServer.start(HandyLogger, nil)
    Logger.configure(level: :none) # suppress crash messages
    # Note: parameter different
    Chorex.start(Recover3TestChor.Chorex, %{Rec3Alice => MyRec3Alice, Rec3Bob => MyRec3Bob}, [l1, l2])

    assert_receive {:chorex_return, Rec3Bob, 4}
    assert [:failed] = GenServer.call(l1, :flush)
    assert [:failed] = GenServer.call(l2, :flush)
    Logger.configure(level: :all)
  end
end

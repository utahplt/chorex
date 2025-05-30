defmodule CrashyLoopTest do
  use ExUnit.Case
  import Chorex

  defmodule CrashyNestedLoop do
    defchor [CnRunner, CnMonitor] do
      def run(CnMonitor.(laps)) do
        loop_try(CnMonitor.(laps), CnRunner.(0))
      end

      def loop_try(CnMonitor.(laps), CnRunner.(lap_no)) do
        try do
          CnMonitor.work_hard()
          CnRunner.work_hard()
          CnRunner.(lap_no) ~> CnMonitor.(l)

          if CnMonitor.(l < laps) do
            CnMonitor.maybe_explode?(0)
            # CnMonitor.(l + 1) ~> CnRunner.(new_no)
            # loop_try(CnMonitor.(laps), CnRunner.(new_no))

            loop_try(CnMonitor.(laps), CnRunner.(lap_no + 1))
          else
            CnMonitor.(:done)
            CnRunner.(:finished)
          end
        rescue
          loop_try(CnMonitor.(laps), CnRunner.(lap_no + 1))
        end
      end
    end
  end

  defmodule MyCrashyNestedRunner do
    use CrashyNestedLoop.Chorex, :cnrunner

    @impl true
    def work_hard() do
      for i <- 0..1000 do
        :crypto.hash(:sha256, "foo#{i}")
      end
      |> length()
    end
  end

  defmodule MyCrashyNestedMonitor do
    use CrashyNestedLoop.Chorex, :cnmonitor

    @impl true
    def maybe_explode?(x) do
      1 / x
    end

    @impl true
    def work_hard() do
      for i <- 0..1000 do
        :crypto.hash(:sha256, "foo#{i}")
      end
      |> length()
    end
  end

  test "finishes" do
    # suppress crash messages
    Logger.configure(level: :alert)

    Chorex.start(
      CrashyNestedLoop.Chorex,
      %{CnRunner => MyCrashyNestedRunner, CnMonitor => MyCrashyNestedMonitor},
      [3]
    )

    assert_receive {:chorex_return, CnRunner, _}, 500
    assert_receive {:chorex_return, CnMonitor, _}, 500
    # restore
    Logger.configure(level: :warning)
  end
end

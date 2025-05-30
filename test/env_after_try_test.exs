defmodule EnvAfterTryTest do
  use ExUnit.Case
  import Chorex

  quote do
    defchor [CRunner, CMonitor] do
      def run(CMonitor.(laps)) do
        loop_try(CMonitor.(laps), CRunner.(0))
      end

      def loop_try(CMonitor.(laps), CRunner.(lap_no)) do
        CRunner.(lap_no) ~> CMonitor.(l)
        CRunner.(dbg(lap_no))
        try do
          CMonitor.go_boom()
        rescue
          CMonitor.(:good_now)
        end

        if CMonitor.(l >= laps) do
          CMonitor.(:done)
          CRunner.(:finished)
        else
          CRunner.(dbg(lap_no))
          loop_try(CMonitor.(laps), CRunner.(lap_no + 1))
          CMonitor.work_hard()
          CRunner.work_hard()
        end
      end
    end

  end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule CrashyLoop do
    defchor [CRunner, CMonitor] do
      def run(CMonitor.(laps)) do
        loop_try(CMonitor.(laps), CRunner.(0))
      end

      def loop_try(CMonitor.(laps), CRunner.(lap_no)) do
        CRunner.(lap_no) ~> CMonitor.(l)
        try do
          CMonitor.go_boom(0)
        rescue
          CMonitor.(:good_now)
        end

        if CMonitor.(l >= laps) do
          CMonitor.(:done)
          CRunner.(:finished)
        else
          CMonitor.work_hard()
          CRunner.work_hard()
          loop_try(CMonitor.(laps), CRunner.(lap_no + 1))
        end
      end
    end
  end

  defmodule MyCrashyRunner do
    use CrashyLoop.Chorex, :crunner

    @impl true
    def work_hard() do
      for i <- 0..1000 do
        :crypto.hash(:sha256, "foo#{i}")
      end
      |> length()
    end
  end

  defmodule MyCrashyMonitor do
    use CrashyLoop.Chorex, :cmonitor

    @impl true
    def go_boom(x) do
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

  test "crashy loop survives" do
    Logger.configure(level: :alert) # suppress crash messages
    Chorex.start(CrashyLoop.Chorex, %{CRunner => MyCrashyRunner, CMonitor => MyCrashyMonitor}, [100])

    assert_receive {:chorex_return, CRunner, :finished}, 1000
    Logger.configure(level: :warning) # restore
  end
end

defmodule LoopRecoverTest do
  use ExUnit.Case
  import Chorex

  defmodule LooprecChor do
    defchor [LooprecAlice, LooprecBob] do
      def run(LooprecAlice.(times)) do
        loop_try(LooprecAlice.(times), LooprecBob.(0))
      end

      def loop_try(LooprecAlice.(laps), LooprecBob.(n)) do
        LooprecBob.(n) ~> LooprecAlice.(l)
        if LooprecAlice.(l <= laps) do
          checkpoint do
            LooprecAlice.work_hard()
            LooprecBob.work_hard()
          rescue
            LooprecAlice.work_hard()
            LooprecBob.work_hard()
          end
          loop_try(LooprecAlice.(laps), LooprecBob.(n + 1))
        else
          LooprecAlice.(:done)
          LooprecBob.(:finished)
        end
      end
    end
  end

  defmodule MyLooprecBob do
    use LooprecChor.Chorex, :looprecbob

    @impl true
    def work_hard() do
      # IO.puts(".")
      for i <- 0..1000 do
        :crypto.hash(:sha256, "foo#{i}")
      end
      |> length()
    end
  end

  defmodule MyLooprecAlice do
    use LooprecChor.Chorex, :looprecalice

    @impl true
    def work_hard() do
      # IO.puts(".")
      for i <- 0..1000 do
        :crypto.hash(:sha256, "foo#{i}")
      end
      |> length()
    end
  end

  test "small loop choreography with checkpoint/rescue" do
    Chorex.start(LooprecChor.Chorex, %{LooprecAlice => MyLooprecAlice, LooprecBob => MyLooprecBob}, [100])
    assert_receive {:chorex_return, LooprecBob, :finished}, 500
  end
end


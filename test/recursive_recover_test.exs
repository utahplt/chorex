defmodule RecursiveRecoverTest do
  use ExUnit.Case
  import Chorex

  defmodule RecRecChor do
    defchor [RecRecAlice, RecRecBob] do
      def run(RecRecAlice.(times)) do
        loop(RecRecAlice.(times), RecRecBob.(1))
      end

      def loop(RecRecAlice.(i), RecRecBob.(n)) do
        try do
          if RecRecAlice.(i == 0) do
            RecRecAlice.(:done)
            RecRecBob.(n)
          else
            loop(RecRecAlice.(i - 1), RecRecBob.(n + n))
          end
        rescue
          loop(RecRecAlice.(i - 2), RecRecBob.(n + n + n))
        end
      end
    end
  end

  defmodule MyRecRecAlice do
    use RecRecChor.Chorex, :recrecalice
  end

  defmodule MyRecRecBob do
    use RecRecChor.Chorex, :recrecbob
  end

  test "small recursive choreography with try/rescue" do
    Chorex.start(RecRecChor.Chorex, %{RecRecAlice => MyRecRecAlice, RecRecBob => MyRecRecBob}, [3])
    assert_receive {:chorex_return, RecRecBob, 8}, 500
  end

  # test "small rescue-path try/rescue choreography" do
  #   Logger.configure(level: :none) # suppress crash messages
  #   Chorex.start(RecoverTestChor.Chorex, %{RecRecAlice => MyRecRecAlice, RecRecBob => MyRecRecBob}, [1])
  #   assert_receive({:chorex_return, RecRecAlice, 98}, 1_000)
  #   assert_receive({:chorex_return, RecRecBob, 99}, 1_000)
  #   Logger.configure(level: :warning) # restore
  # end
end

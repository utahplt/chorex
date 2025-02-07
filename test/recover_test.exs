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
    Chorex.start(RecoverTestChor.Chorex, %{RecAlice => MyRecAlice, RecBob => MyRecBob}, [1])
    assert_receive({:chorex_return, RecAlice, 98}, 1_000)
    assert_receive({:chorex_return, RecBob, 99}, 1_000)
  end

  # defmodule Recover2TestChor do
  #   defchor [Rec2Alice, Rec2Bob] do
  #     def run(Rec2Alice.(param), Rec2Alice.(logger), Rec2Bob.(logger)) do
  #       Rec2Alice.one() ~> Rec2Bob.(x)
  #       Rec2Bob.two() ~> Rec2Alice.(a)
  #       try do
  #         Rec2Alice.two(a, param) ~> Rec2Bob.(y)
  #         Rec2Bob.(x + y)
  #       rescue
  #         Rec2Alice.log_failure(logger)
  #         Rec2Bob.log_failure(logger)
  #       end
  #       Rec2Alice.(1)
  #       Rec2Bob.(2)
  #     end
  #   end
  # end

  # defmodule MyRec2Alice do
  #   use Recover2TestChor.Chorex, :rec2alice

  #   @impl true
  #   def one(), do: 1

  #   @impl true
  #   def two(a, b) do
  #     dbg(a / (b - 1))
  #   end

  #   @impl true
  #   def log_failure(logger) do
  #     send(logger, :failed)
  #   end
  # end

  # defmodule MyRec2Bob do
  #   use Recover2TestChor.Chorex, :rec2bob

  #   @impl true
  #   def two(), do: 2

  #   @impl true
  #   def log_failure(logger) do
  #     send(logger, :failed)
  #   end
  # end
end

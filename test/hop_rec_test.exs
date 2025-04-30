defmodule HopRecTest do
  use ExUnit.Case
  import Chorex

  defmodule HopRecChor do
    defchor [Hop1, Hop2] do
      def run(Hop1.(hard_work?), Hop2.(iters)) do
        if Hop1.(hard_work?) do
          loop(@hard_work/2, Hop1.(1), Hop2.(iters))
        else
          loop(@easy_work/2, Hop1.(1), Hop2.(iters))
        end
      end

      def loop(work_fn, Hop1.(x), Hop2.(iters)) do
        with Hop1.(y) <- work_fn.(Hop1.(x), Hop2.(iters)) do
          Hop1.(y) ~> Hop2.(z)
          if Hop2.(z >= iters) do
            Hop1.(y)
            Hop2.(:done)
          else
            loop(work_fn, Hop1.(y), Hop2.(iters))
          end
        end
      end

      def hard_work(Hop1.(a), Hop2.(b)) do
        Hop2.(b - (b - 1)) ~> Hop1.(c)
        Hop1.(a + c)
      end

      def easy_work(Hop1.(a), Hop2.(b)) do
        Hop2.(b / 2) ~> Hop1.(c)
        Hop1.(a + c)
      end

    end
  end

  defmodule Hop1Impl do
    use HopRecChor.Chorex, :hop1
  end

  defmodule Hop2Impl do
    use HopRecChor.Chorex, :hop2
  end

  describe "higher-order with recursion" do
    test "compiles" do
      assert true
    end

    test "runs" do
      Chorex.start(HopRecChor.Chorex, %{Hop1 => Hop1Impl, Hop2 => Hop2Impl}, [true, 10])
      assert_receive {:chorex_return, Hop1, 10}, 500
      assert_receive {:chorex_return, Hop2, :done}, 500

      Chorex.start(HopRecChor.Chorex, %{Hop1 => Hop1Impl, Hop2 => Hop2Impl}, [false, 10])
      assert_receive {:chorex_return, Hop1, 11.0}, 500
      assert_receive {:chorex_return, Hop2, :done}, 500
    end
  end
end

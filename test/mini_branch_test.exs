defmodule MiniBranchTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniBranchChor do
    defchor [MbAlice, MbBob] do
      def run(MbAlice.(x)) do
        MbAlice.one(x) ~> MbBob.(x)
        if MbBob.go(x), notify: [MbAlice] do
          MbAlice.two() ~> MbBob.(y)
          MbBob.({x, y})
        else
          MbBob.(x + 7) ~> MbAlice.(y) # 2 + 7 = 9 -> MbAlice.y
          MbAlice.(y + 1) ~> MbBob.(y) # 10 -> MbBob.y
          compute(MbBob.(y))         # 22
        end
      end

      def compute(MbBob.(a)) do
        MbBob.(a + 1) ~> MbAlice.(b)
        MbAlice.(b + 1) ~> MbBob.c
        MbBob.(c + a)
      end
    end
  end

  defmodule MyMbAlice do
    use MiniBranchChor.Chorex, :mbalice

    @impl true
    def one(x), do: x + 1

    @impl true
    def two(), do: 2
  end

  defmodule MyMbBob do
    use MiniBranchChor.Chorex, :mbbob

    @impl true
    def go(x), do: x > 5
  end

  test "small choreography with branch" do
    Chorex.start(MiniBranchChor.Chorex, %{MbAlice => MyMbAlice, MbBob => MyMbBob}, [7])
    assert_receive {:chorex_return, MbBob, {8, 2}}
  end

  test "small choreography with branch and function call" do
    Chorex.start(MiniBranchChor.Chorex, %{MbAlice => MyMbAlice, MbBob => MyMbBob}, [1])
    assert_receive {:chorex_return, MbBob, 22}
  end
end

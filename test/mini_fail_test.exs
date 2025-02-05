defmodule MiniFailTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniFailTestChor do
    defchor [MftAlice, MftBob] do
      def run(MftAlice.(param)) do
        MftAlice.one() ~> MftBob.(x)
        MftBob.two() ~> MftAlice.(a)
        try do
          MftAlice.two(a, param) ~> MftBob.(y)
          MftBob.(x + y)
        rescue
          MftAlice.(99)
          MftBob.(99)
        end
        # FIXME: write a program with a non-tail-position try/rescue
      end
    end
  end

  defmodule MyMftAlice do
    use MiniFailTestChor.Chorex, :mftalice

    @impl true
    def one(), do: 1

    @impl true
    def two(a, b) do
      dbg(a / (b - 1))
    end
  end

  defmodule MyMftBob do
    use MiniFailTestChor.Chorex, :mftbob

    @impl true
    def two(), do: 2
  end

  test "small happy-path try/rescue choreography" do
    Chorex.start(MiniFailTestChor.Chorex, %{MftAlice => MyMftAlice, MftBob => MyMftBob}, [2])
    assert_receive {:chorex_return, MftBob, 42}, 500
  end

  # test "small rescue-path try/rescue choreography" do
  #   Chorex.start(MiniFailTestChor.Chorex, %{MftAlice => MyMftAlice, MftBob => MyMftBob}, [1])
  #   assert_receive({:chorex_return, MftBob, 42}, 1_000)
  # end
end

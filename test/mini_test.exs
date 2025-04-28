defmodule MiniTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniTestChor do
    defchor [MtAlice, MtBob] do
      def run() do
        MtAlice.one() ~> MtBob.(x)
        MtAlice.two() ~> MtBob.(y)
        MtBob.work(x + y)
      end
    end
  end

  defmodule MyMtAlice do
    use MiniTestChor.Chorex, :mtalice

    @impl true
    def one(), do: 40

    @impl true
    def two(), do: 2
  end

  defmodule MyMtBob do
    use MiniTestChor.Chorex, :mtbob

    @impl true
    def work(n) do
      n
    end
  end

  test "smallest choreography test" do
    Chorex.start(MiniTestChor.Chorex, %{MtAlice => MyMtAlice, MtBob => MyMtBob}, [])
    assert_receive({:chorex_return, MtBob, 42}, 500)
  end
end

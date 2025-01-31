defmodule MiniVarOverwriteTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniVarOverwriteTestChor do
    defchor [MtvoAlice, MtvoBob] do
      def run() do
        MtvoAlice.one() ~> MtvoBob.(x)
        MtvoAlice.two() ~> MtvoBob.(x)
        MtvoBob.(x + 1)
      end
    end
  end

  defmodule MyMtvoAlice do
    use MiniVarOverwriteTestChor.Chorex, :mtvoalice

    @impl true
    def one(), do: 40

    @impl true
    def two(), do: 2
  end

  defmodule MyMtvoBob do
    use MiniVarOverwriteTestChor.Chorex, :mtvobob
  end

  test "shadowed var is correct" do
    Chorex.start(MiniVarOverwriteTestChor.Chorex, %{MtvoAlice => MyMtvoAlice, MtvoBob => MyMtvoBob}, [])
    assert_receive({:chorex_return, MtvoBob, 3})
  end
end

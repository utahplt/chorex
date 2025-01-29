defmodule MiniFailTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniFailTestChor do
    defchor [MftAlice, MftBob] do
      def run() do
        MftAlice.one() ~> MftBob.(x)
        MftBob.zero() ~> MftAlice.(a)
        MftAlice.two(a) ~> MftBob.(y)
        MftBob.(x + y)
      end
    end
  end

  defmodule MyMftAlice do
    use MiniFailTestChor.Chorex, :mftalice

    @impl true
    def one(), do: 40

    @impl true
    def two(a) do
      4 / a
    end
  end

  defmodule MyMftBob do
    use MiniFailTestChor.Chorex, :mftbob

    @impl true
    def zero(), do: 0
  end

  test "smallest choreography test" do
    Chorex.start(MiniFailTestChor.Chorex, %{MftAlice => MyMftAlice, MftBob => MyMftBob}, [])
    assert_receive({:chorex_return, MftBob, 42})
  end
end

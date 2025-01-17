defmodule MiniFuncallTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniFcChor do
    defchor [Alice, Bob] do
      def run() do
        Alice.one() ~> Bob.(x)
        with Bob.(z) <- compute(Bob.(x)) do
          Alice.two() ~> Bob.(y)
          Bob.({x, y, z})
        end
      end

      def compute(Bob.(a)) do
        Bob.(a + 1) ~> Alice.(b)
        Alice.(b + 1) ~> Bob.c
        Bob.(c + a)
      end
    end
  end

  defmodule MyAlice do
    use MiniFcChor.Chorex, :alice

    @impl true
    def one(), do: 40

    @impl true
    def two(), do: 2
  end

  defmodule MyBob do
    use MiniFcChor.Chorex, :bob
  end

  test "small choreography with function call" do
    Chorex.start(MiniFcChor.Chorex, %{Alice => MyAlice, Bob => MyBob}, [])
    assert_receive({:chorex_return, Bob, {40, 2, 82}})
  end
end

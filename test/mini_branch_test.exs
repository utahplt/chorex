defmodule MiniBranchTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniBranchChor do
    defchor [Alice, Bob] do
      def run(Alice.(x)) do
        Alice.one(x) ~> Bob.(x)
        if Bob.go(x), notify: [Alice] do
          Alice.two() ~> Bob.(y)
          Bob.({x, y})
        else
          Bob.(x + 7) ~> Alice.(y) # 2 + 7 = 9 -> Alice.y
          Alice.(y + 1) ~> Bob.(y) # 10 -> Bob.y
          compute(Bob.(y))         # 22
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
    use MiniBranchChor.Chorex, :alice

    @impl true
    def one(x), do: x + 1

    @impl true
    def two(), do: 2
  end

  defmodule MyBob do
    use MiniBranchChor.Chorex, :bob

    @impl true
    def go(x), do: x > 5
  end

  test "small choreography with branch" do
    Chorex.start(MiniBranchChor.Chorex, %{Alice => MyAlice, Bob => MyBob}, [7])
    assert_receive {:chorex_return, Bob, {8, 2}}
  end

  test "small choreography with branch and function call" do
    Chorex.start(MiniBranchChor.Chorex, %{Alice => MyAlice, Bob => MyBob}, [1])
    assert_receive {:chorex_return, Bob, 22}
  end
end

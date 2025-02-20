defmodule MiniWithTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniWithChor do
    defchor [MwAlice, MwBob] do
      def run() do
        MwAlice.one() ~> Bob.(x)
        # watch out! 2-tuples don't look like 3- or higher tuples!
        with {MwAlice.(y), MwBob.(y)} <- derez(Bob.(x)) do
          MwAlice.two(y) ~> MwBob.(z)
          MwBob.({x, y, z})
        end
        MwAlice.(:end_of_line)
      end

      def derez(MwBob.(a)) do
        MwBob.(a + 1) ~> MwAlice.(b)
        MwBob.(a + 1)
        MwAlice.(b * 2)
      end
    end
  end

  defmodule MyMwAlice do
    use MiniWithChor.Chorex, :mwalice

    def one(), do: 40
    def two(y), do: y + 1
  end

  defmodule MyMwBob do
    use MiniWithChor.Chorex, :mwbob
  end

  test "mini test of with not in tail position and supporting multiple receives" do
    Chorex.start(MiniWithChor.Chorex, %{MwAlice => MyMwAlice, MwBob => MyMwBob}, [])

    assert_receive {:chorex_return, MwAlice, :end_of_line}
    assert_receive {:chorex_return, MwBob, {40, 41, 83}}
  end
end

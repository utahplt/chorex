defmodule MiniFuncallTest do
  use ExUnit.Case
  import Chorex

  defmodule MiniFcChor do
    defchor [Mfcalice, MfcBob] do
      def run() do
        Mfcalice.one() ~> MfcBob.(x)
        with MfcBob.(z) <- compute(MfcBob.(x)) do
          Mfcalice.two() ~> MfcBob.(y)
          MfcBob.({x, y, z})
        end
      end

      def compute(MfcBob.(a)) do
        MfcBob.(a + 1) ~> Mfcalice.(b)
        Mfcalice.(b + 1) ~> MfcBob.c
        MfcBob.(c + a)
      end
    end
  end

  defmodule MyMfcAlice do
    use MiniFcChor.Chorex, :mfcalice

    @impl true
    def one(), do: 40

    @impl true
    def two(), do: 2
  end

  defmodule MyMfcBob do
    use MiniFcChor.Chorex, :mfcbob
  end

  test "small choreography with function call" do
    Chorex.start(MiniFcChor.Chorex, %{Mfcalice => MyMfcAlice, MfcBob => MyMfcBob}, [])
    assert_receive {:chorex_return, MfcBob, {40, 2, 82}}
  end
end

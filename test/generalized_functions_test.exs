defmodule GeneralizedFunctionsTest do
  use ExUnit.Case
  import Chorex

  quote do
    defchor [Alice, Bob] do
      def main(func, Alice.(c)) do
        with Alice.(a) <- func.(Alice.get_b(c)) do
          Alice.(a) ~> Bob.(b)
        end
      end

      def f1(Alice.(x), Bob.(y)) do
        Bob.(y) ~> Alice.(y)
        Alice.(x + y)
      end

      def f2(Alice.(x)) do
        Alice.(x * 2)
      end

      def run(_) do
        # main(&f1/1)
        # main(@f1/1)
        f1(Alice.(42), Bob.(17))
        # Alice.(&should_be_local/3, 42)
        main(@f2/1, Alice.(6))
      end
    end
  end
  |> Macro.expand_once(__ENV__)
  |> Macro.to_string()
  |> IO.puts()
end

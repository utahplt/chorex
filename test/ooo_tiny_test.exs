defmodule OooTinyTest do
  use ExUnit.Case

  import Chorex

  # quote do
  #   defchor [O3Alice, O3Bob] do
  #     def run() do
  #       O3Alice.one() ~> O3Bob.(x)
  #       O3Alice.two() ~> O3Bob.(y)
  #       O3Bob.(x + 1) ~> O3Alice.(one_plus_1)
  #       O3Bob.(x + y)
  #       # FIXME: I don't think I can do free variable analysis with things like "foo.x"
  #       O3Alice.(one_plus_1 * 7)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule OooSmol do
    defchor [O3Alice, O3Bob] do
      def run() do
        O3Alice.one() ~> O3Bob.(x)
        O3Alice.two() ~> O3Bob.(y)
        O3Bob.(x + 1) ~> O3Alice.(one_plus_1)
        O3Bob.(x + y)
        # FIXME: I don't think I can do free variable analysis with things like "foo.x"
        O3Alice.(one_plus_1 * 7)
      end
    end
  end
end

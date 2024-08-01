defmodule GeneralizedFunctionsTest do
  # use ExUnit.Case
  # import Chorex

  # quote do
  #   defchor [Alice, Bob] do
  #     def main(func, Alice.(c)) do
  #       with Alice.(a) <- func.(Alice.get_b(c)) do
  #         Alice.(a) ~> Bob.(b)
  #       end
  #     end

  #     def f1(Alice.({:ok, x}), Bob.(y)) do
  #       Bob.(y) ~> Alice.(y)
  #       Alice.(x + y)
  #     end

  #     def f2(Alice.(x)) do
  #       Alice.(x * 2)
  #     end

  #     def run() do
  #       f1(Alice.({:ok, 42}), Bob.(17))
  #       Alice.foobar(&should_be_local/3, 42)
  #       Alice.foobar(&Enum.should_be_remote/3, 42)
  #       main(@f2/1, Alice.(6))
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()
end

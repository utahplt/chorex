defmodule FreeVarAnalysisTest do
  use ExUnit.Case

  import FreeVarAnalysis
  doctest FreeVarAnalysis

  describe "extract_pattern_vars/2" do
    test "simple variable" do
      expr = quote do: x
      assert {[], [{:x, _, _}]} = extract_pattern_vars(expr)
    end

    test "ignore _ in patterns" do
      expr = quote do: {x, _, x}
      assert {[], [{:x, _, _}]} = extract_pattern_vars(expr)
    end

    test "pattern with two variables" do
      expr = quote do: {x, y}
      assert {[], [{:x, _, _}, {:y, _, _}]} = extract_pattern_vars(expr)
    end

    test "pattern with one pinned variable, one binding" do
      expr = quote do: {x, ^y}
      assert {[{:y, _, _}], [{:x, _, _}]} = extract_pattern_vars(expr)
    end

    test "pattern with a map and list" do
      expr = quote do
        {x, %{foo: [_, y | _], bar: ^z, baz: 42}}
      end

      assert {[{:z, _, _}], [{:x, _, _}, {:y, _, _}]} = extract_pattern_vars(expr)
    end

    test "pattern with an equals" do
      expr = quote do
               {{v, _, _} = func_name, _, [^arg1 | arg_rest]}
      end

      assert {[{:arg1, _, _}], [{:arg_rest, _, _}, {:func_name, _, _}, {:v, _, _}]} = extract_pattern_vars(expr)
    end
  end

  describe "free_vars/2" do
    @describetag :skip
    test "simple variable" do
      ast = quote do: x
      assert free_vars(ast) == [:x]
    end

    @describetag :skip
    test "function with free variable" do
      ast = quote do: fn y -> x + y end
      assert free_vars(ast) == [:x]
    end

    @describetag :skip
    test "nested function with multiple free vars" do
      ast = quote do: fn a -> fn b -> x + y + a + b end end
      assert free_vars(ast) == [:x, :y]
    end

    @describetag :skip
    test "no free variables" do
      ast = quote do: fn x -> x end
      assert free_vars(ast) == []
    end

    @describetag :skip
    test "complex expression" do
      ast = quote do: fn a -> b + (fn c -> a + b + c + d end) end
      assert free_vars(ast) == [:b, :d]
    end

    @describetag :skip
    test "multiple clauses" do
      ast = quote do: fn
        x -> y + x
        z -> y + w + z
      end
      assert free_vars(ast) == [:y, :w]
    end
  end
end

defmodule WriterMonadTest do
  use ExUnit.Case
  doctest WriterMonad
  import WriterMonad

  test "basic do monad" do
    foo = monadic do
      thing1 <- return(5)
      thing2 <- {thing1 + 2, ["foo"], [:baz]}
      thing3 <- {thing1 + thing2, ["bar"], [:quux]}
      return thing3
    end

    assert {12, ["bar", "foo"], [:baz, :quux]} = foo
  end
end

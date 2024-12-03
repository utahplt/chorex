defmodule WriterMonadTest do
  use ExUnit.Case
  doctest WriterMonad
  import WriterMonad

  test "basic do monad" do
    foo =
      monadic do
        thing1 <- return(5)
        thing2 <- {thing1 + 2, ["foo"], [:baz]}
        thing3 <- {thing1 + thing2, ["bar"], [:quux]}
        return(thing3)
      end

    assert {12, ["bar", "foo"], [:baz, :quux]} = foo
  end

  def t1(thing) do
    thing + 1
  end

  test "fmap" do
    assert {2, [1], []} = fmap(return(1, [1]), &t1/1)
    assert {3, [2], []} = return(2, [2]) <~> &t1/1
  end

  describe "flatten_block/1" do
    test "flattens the basics" do
      mt =
        quote do
        end

      mt2 =
        quote do
          unquote(mt)
        end

      mt2b =
        quote do
          unquote(mt2)
        end

      mt3 =
        quote do
          unquote(mt)
          unquote(mt)
        end

      mt4 =
        quote do
          unquote(mt)
          unquote(mt2)
        end

      mt5 =
        quote do
          unquote(mt)
          unquote(mt4)
          unquote(mt2)
          unquote(mt)
        end

      assert ^mt = flatten_block(mt2)
      assert ^mt = flatten_block(mt2b)
      assert ^mt = flatten_block(mt3)
      assert ^mt = flatten_block(mt4)
      assert ^mt = flatten_block(mt5)
    end
  end
end

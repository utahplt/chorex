defmodule UtilsTest do
  use ExUnit.Case
  doctest Utils

  test "fresh_atom/1" do
    a1 = Utils.fresh_atom("foo")
    a2 = Utils.fresh_atom("foo")

    assert a1 != a2
  end
end

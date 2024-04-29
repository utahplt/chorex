defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  test "smoke" do
    assert ( defchor foo(Alice, Bob, Eve), do: "hello, world" ) == 42
  end
end

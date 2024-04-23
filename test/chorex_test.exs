defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex

  test "greets the world" do
    assert Chorex.hello() == :world
  end
end

defmodule UtilsTest do
  use ExUnit.Case
  doctest Utils

  test "fresh_atom/1" do
    a1 = Utils.fresh_atom("foo")
    a2 = Utils.fresh_atom("foo")

    assert a1 != a2
  end

  describe "assoc functions" do
    test "assoc_put" do
      a1 = Utils.assoc_put([], :foo, 1)
      assert [{:foo, 1}] = a1
      a2 = Utils.assoc_put(a1, :bar, 2)
      assert [{:bar, 2}, {:foo, 1}] = a2
      a3 = Utils.assoc_put(a2, :foo, 3)
      assert [{:foo, 3}, {:bar, 2}, {:foo, 1}] = a3
    end

    test "assoc_del" do
      a1 = Utils.assoc_put([], :foo, 1)
      a2 = Utils.assoc_put(a1, :bar, 2)
      a3 = Utils.assoc_put(a2, :foo, 3)

      assert ^a2 = Utils.assoc_del(a3, :foo)
      assert [{:foo, 3}, {:foo, 1}] = Utils.assoc_del(a3, :bar)
      assert [] = Utils.assoc_del(a1, :foo)
      assert [] = Utils.assoc_del([], :foo)
    end

    test "assoc_get" do
      a1 = Utils.assoc_put([], :foo, 1)
      a2 = Utils.assoc_put(a1, :bar, 2)
      a3 = Utils.assoc_put(a2, :foo, 3)

      assert {:foo, 3} = Utils.assoc_get(a3, :foo)
      assert {:bar, 2} = Utils.assoc_get(a3, :bar)
      assert {:foo, 1} = Utils.assoc_get(a2, :foo)
    end
  end
end

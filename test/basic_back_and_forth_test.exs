defmodule BasicBackAndForthTest do
  use ExUnit.Case
  import Chorex

  test "back-and-forth messaging work" do
    stx = quote do
      def run() do
        Buyer.get_book_title() ~> Seller.(b)
        Seller.get_price("book:" <> b) ~> Buyer.(p)
        Buyer.(:whatever) ~> Seller.(wat)
        Seller.order_book(b, wat)
        Buyer.(p + 2)
      end
    end

    assert {_new_stx, _callbacks, _fresh_funcs} = project(stx, __ENV__, Seller, empty_ctx(__ENV__))
  end
end

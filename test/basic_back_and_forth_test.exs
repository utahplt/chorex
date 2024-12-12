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

    assert {new_stx, callbacks, fresh_funcs} = project(stx, __ENV__, Seller, empty_ctx(__ENV__))

    new_stx |> Macro.to_string() |> IO.puts()

    for {n, f} <- fresh_funcs do
      dbg(n)
      f |> Macro.to_string() |> IO.puts()
    end
  end
end

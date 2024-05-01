defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  def yadda do
    quote do
      defchor [Buyer, Seller] do
        Buyer.get_book_title() ~> Seller.b()
        Seller.get_price(b) ~> Buyer.p()
        return(Buyer.p())
      end
    end
    |> Macro.expand_once(__ENV__)
    |> Macro.to_string()
    |> IO.puts()

    42
  end

  defmodule TestChor do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.b
      Seller.get_price(b) ~> Buyer.q
      return(Buyer.r)
    end
  end

  test "smoke" do
    assert yadda() == 42
  end
end

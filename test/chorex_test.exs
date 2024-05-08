defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # quote do
  #   defchor [Buyer, Seller] do
  #     Buyer.get_book_title() ~> Seller.b
  #     Seller.get_price("foo" <> b) ~> Buyer.p
  #     return(Buyer.(p/2))
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> IO.inspect()
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule TestChor do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.b
      Seller.get_price("book:" <> b) ~> Buyer.p
      return(Buyer.(p + 2))
    end
  end

  defmodule MyBuyer do
    use TestChor.Chorex, :buyer

    def get_book_title(), do: "Das Glasperlenspiel"
  end

  defmodule MySeller do
    use TestChor.Chorex, :seller

    def get_price("book:Das Glasperlenspiel"), do: 40
    def get_price(_), do: 0
  end

  test "module compiles" do
    # If we see this, the choreography compiled!
    assert 40 + 2 == 42
  end

  test "choreography runs" do
    ps = spawn(MySeller, :init, [])
    pb = spawn(MyBuyer, :init, [])

    config = %{Seller => ps, Buyer => pb, :super => self()}

    send(ps, {:config, config})
    send(pb, {:config, config})

    assert_receive {:choreography_return, 42}
  end
end

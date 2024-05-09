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

  #
  # More complex choreographies
  #

  defmodule TestChor2 do
    defchor [Buyer1, Buyer2, Seller1] do
      Buyer1.get_book_title() ~> Seller1.b
      Seller1.get_price("book:" <> b) ~> Buyer1.p
      Seller1.get_price("book:" <> b) ~> Buyer2.p
      # Buyer2.(p / 2) ~> Buyer1.contrib
      Buyer2.compute_contrib(p) ~> Buyer1.contrib

      if Buyer1.(p - contrib < get_budget()) do
        Buyer1[L] ~> Seller1
        Buyer1.get_address() ~> Seller1.addr
        Seller.get_delivery_date(b, addr) ~> Buyer1.d_date
        return(Buyer1.d_date)
      else
        Buyer1[R] ~> Seller1
        return(Buyer1.(nil))
      end
    end
  end
end

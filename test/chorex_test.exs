defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # def yadda do
  #   quote do
  #     defchor [Buyer, Seller] do
  #       Buyer.get_book_title() ~> Seller.b()
  #       Seller.get_price(b) ~> Buyer.q
  #       return(Buyer.q)
  #     end
  #   end
  #   # |> IO.inspect(label: "before")
  #   |> Macro.expand_once(__ENV__)
  #   # |> IO.inspect(label: "after")
  #   |> Macro.to_string()
  #   |> IO.puts()

  #   42
  # end

  quote do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.b
      Seller.get_price(b) ~> Buyer.zoop
      return(Buyer.zoop)
    end
  end
  |> Macro.expand_once(__ENV__)
  |> Macro.to_string()
  |> IO.puts()

  defmodule TestChor do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.b
      Seller.get_price(b) ~> Buyer.zoop
      return(Buyer.zoop)
    end
  end

  defmodule MyBuyer do
    use TestChor.Chorex, :buyer

    def get_book_title(), do: "Das Glasperlenspiel"
  end

  defmodule MySeller do
    use TestChor.Chorex, :seller

    def get_price(_b), do: IO.inspect(42, label: "get_price sends")
  end

  test "module compiles" do
    # If we see this, the choreography compiled!
    assert 40 + 2 == 42
  end

  test "choreography runs" do
    ps = spawn(MySeller, :init, [])
    pb = spawn(MyBuyer, :init, [])

    config = %{Seller => ps, Buyer => pb}
    IO.inspect(config, label: "config")

    send(ps, {:config, config})
    send(pb, {:config, config})
  end
end

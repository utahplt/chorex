defmodule ProxiedActorTest do
  use ExUnit.Case
  import Chorex

  defmodule BooksellerProxied do
	defchor [Buyer, {Seller, :singleton}] do
      Buyer.get_book_title() ~> Seller.(b)
      Seller.get_price(b) ~> Buyer.(p)
      if Buyer.in_budget(p) do
        Buyer[L] ~> Seller
        if Seller.acquire_book() do
          Seller[L] ~> Buyer
          Buyer.(:book_get)
        else
          Seller[R] ~> Buyer
          Buyer.(:darn_missed_it)
        end
      else
        Buyer[R] ~> Seller
        Buyer.(:nevermind)
      end
    end
  end

  defmodule MyBuyer do
    use BooksellerProxied.Chorex, :buyer

    def get_book_title(), do: "Anathem"
    def in_budget(_), do: true
  end

  defmodule MySellerBackend do
    use BooksellerProxied.Chorex, :seller

    def get_price(_), do: 42

    def acquire_book() do
      # Attempt to acquire a lock on the book
      Proxy.update_state()
    end
  end
end

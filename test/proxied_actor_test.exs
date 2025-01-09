defmodule ProxiedActorTest do
  use ExUnit.Case
  import Chorex
  alias Chorex.Proxy

  # quote do
  #   defchor [BuyerP, {SellerP, :singleton}] do
  #     def run() do
  #       BuyerP.get_book_title() ~> SellerP.(b)
  #       SellerP.get_price(b) ~> BuyerP.(p)

  #       if BuyerP.in_budget(p) do
  #         BuyerP[L] ~> SellerP

  #         if SellerP.acquire_book(@chorex_config, b) do
  #           SellerP[L] ~> BuyerP
  #           BuyerP.(:book_get)
  #         else
  #           SellerP[R] ~> BuyerP
  #           BuyerP.(:darn_missed_it)
  #         end
  #       else
  #         BuyerP[R] ~> SellerP
  #         BuyerP.(:nevermind)
  #       end
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule BooksellerProxied do
    defchor [BuyerP, {SellerP, :singleton}] do
      def run() do
        BuyerP.get_book_title() ~> SellerP.(b)
        SellerP.get_price(b) ~> BuyerP.(p)

        if BuyerP.in_budget(p) do
          BuyerP[L] ~> SellerP

          if SellerP.acquire_book(@chorex_config, b) do
            SellerP[L] ~> BuyerP
            BuyerP.(:book_get)
          else
            SellerP[R] ~> BuyerP
            BuyerP.(:darn_missed_it)
          end
        else
          BuyerP[R] ~> SellerP
          BuyerP.(:nevermind)
        end
      end
    end
  end

  defmodule MyBuyerP do
    use BooksellerProxied.Chorex, :buyerp

    def get_book_title(), do: "Anathem"
    def in_budget(_), do: true
  end

  defmodule MySellerPBackend do
    use BooksellerProxied.Chorex, :sellerp
    alias Chorex.Proxy

    def get_price(_), do: 42

    def acquire_book(config, book_title) do
      # Attempt to acquire a lock on the book
      Proxy.update_state(config, fn book_stock ->
        with {:ok, count} <- Map.fetch(book_stock, book_title) do
          if count > 0 do
            # Have the book, lock it for this customer
            {true, Map.put(book_stock, book_title, count - 1)}
          else
            {false, book_stock}
          end
        else
          :error ->
            {false, book_stock}
        end
      end)
    end
  end

  @tag :skip
  test "basic: one buyer can get a book" do
    {:ok, px} = GenServer.start(Chorex.Proxy, %{"Anathem" => 1})

    Chorex.start(
      BooksellerProxied.Chorex,
      %{BuyerP => MyBuyerP, SellerP => {MySellerPBackend, px}},
      []
    )

    assert_receive {:chorex_return, BuyerP, :book_get}
  end

  # test "basic: one buyer can get a book" do
  #   b1 = spawn(MyBuyerP, :init, [[]])
  #   {:ok, px} = GenServer.start(Chorex.Proxy, %{"Anathem" => 1})

  #   Proxy.begin_session(px, [b1], MySellerPBackend, :init, [])
  #   config = %{BuyerP => b1, SellerP => px, :super => self()}
  #   send(b1, {:config, config})
  #   send(px, {:chorex, b1, {:config, config}})

  #   assert_receive {:chorex_return, BuyerP, :book_get}
  # end

  @tag :skip
  test "two buyers try for the book, one gets it" do
    {:ok, px} = GenServer.start(Chorex.Proxy, %{"Anathem" => 1})

    Chorex.start(
      BooksellerProxied.Chorex,
      %{BuyerP => MyBuyerP, SellerP => {MySellerPBackend, px}},
      []
    )

    Chorex.start(
      BooksellerProxied.Chorex,
      %{BuyerP => MyBuyerP, SellerP => {MySellerPBackend, px}},
      []
    )

    assert_receive {:chorex_return, BuyerP, :book_get}
    assert_receive {:chorex_return, BuyerP, :darn_missed_it}
    # only one instance of book_get
    refute_receive {:chorex_return, BuyerP, :book_get}
  end
end

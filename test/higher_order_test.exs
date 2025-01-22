defmodule HigherOrderTest do
  use ExUnit.Case
  import Chorex

  defmodule TestChor3 do
    defchor [Buyer3, Contributor3, Seller3] do
      def bookseller(decision_func) do
        Buyer3.get_book_title() ~> Seller3.(the_book)

        with Buyer3.(decision) <- decision_func.(Seller3.get_price("book:" <> the_book)) do
          if Buyer3.(decision) do
            Buyer3.get_address() ~> Seller3.(the_address)
            Seller3.get_delivery_date(the_book, the_address) ~> Buyer3.(d_date)
            Buyer3.(d_date)
          else
            Buyer3.(nil)
          end
        end
      end

      def one_party(Seller3.(the_price)) do
        Seller3.(the_price) ~> Buyer3.(p)
        Buyer3.(p < get_budget())
      end

      def two_party(Seller3.(the_price)) do
        Seller3.(the_price) ~> Buyer3.(p)
        Seller3.(the_price) ~> Contributor3.(p)
        Contributor3.compute_contrib(p) ~> Buyer3.(contrib)
        Buyer3.(p - contrib < get_budget())
      end

      def run(Buyer3.(include_contributions?)) do
        if Buyer3.(include_contributions?) do
          bookseller(@two_party/1)
        else
          bookseller(@one_party/1)
        end
      end
    end
  end

  defmodule MySeller3 do
    use TestChor3.Chorex, :seller3

    @impl true
    def get_delivery_date(_book, _addr) do
      # IO.puts("getting delivery date for")
      ~D[2024-05-13]
    end

    @impl true
    def get_price("book:Das Glasperlenspiel"), do: 42
    def get_price("book:Zen and the Art of Motorcycle Maintenance"), do: 13
  end

  defmodule MyBuyer3 do
    use TestChor3.Chorex, :buyer3

    @impl true
    def get_book_title(), do: "Zen and the Art of Motorcycle Maintenance"
    @impl true
    def get_address(), do: "Maple Street"
    @impl true
    def get_budget(), do: 22
  end

  defmodule MyContributor3 do
    use TestChor3.Chorex, :contributor3

    @impl true
    def compute_contrib(price) do
      # IO.inspect(price, label: "Buyer 2 computing contribution of")
      price / 2
    end
  end

  test "3-party higher-order choreography runs" do
    Chorex.start(
      TestChor3.Chorex,
      %{Seller3 => MySeller3, Buyer3 => MyBuyer3, Contributor3 => MyContributor3},
      [true]
    )

    assert_receive {:chorex_return, Buyer3, ~D[2024-05-13]}
  end

  test "2-party higher-order choreography runs" do
    Chorex.start(
      TestChor3.Chorex,
      %{Seller3 => MySeller3, Contributor3 => MyContributor3, Buyer3 => MyBuyer3},
      [false]
    )

    assert_receive {:chorex_return, Buyer3, ~D[2024-05-13]}
  end

  defmodule TestChor4 do
    defchor [Alice, Bob] do
      def big_chor(sandwich_internals) do
        Alice.get_bread() ~> Bob.(bread)

        with Bob.(ingredient_stack) <- sandwich_internals.(Alice.get_allergens()) do
          Bob.make_sandwich(bread, ingredient_stack) ~> Alice.(sammich)
          Alice.(sammich)
        end
      end

      def pbj(Alice.(allergens)) do
        if Alice.allergic_to(allergens, "peanut_butter") do
          Alice.plz_wash() ~> Bob.(wash_hands)
          Bob.dry(wash_hands)
          Bob.(["almond_butter", "raspberry_jam"])
        else
          Bob.(["peanut_butter", "raspberry_jam"])
        end
      end

      def hamncheese(Alice.(allergens)) do
        if Alice.allergic_to(allergens, "dairy") do
          Bob.(["ham", "tomato"])
        else
          Bob.(["ham", "swiss_cheese", "tomato"])
        end
      end

      def run(Alice.(want_pbj?)) do
        if Alice.(want_pbj?) do
          big_chor(@pbj/1)
        else
          big_chor(@hamncheese/1)
        end
      end
    end
  end

  defmodule MyAlice4 do
    use TestChor4.Chorex, :alice

    @impl true
    def get_bread(), do: "Italian herbs and cheese"
    @impl true
    def get_allergens(), do: ["mushroom", "peanut_butter"]
    @impl true
    def allergic_to(lst, thing), do: Enum.any?(lst, fn x -> x == thing end)
    @impl true
    def plz_wash(), do: "purge your hands of peanuts and mushrooms!"
  end

  defmodule MyBob4 do
    use TestChor4.Chorex, :bob

    @impl true
    def dry(x), do: IO.puts("Ok, I cleaned my hands: #{x}")

    @impl true
    def make_sandwich(bread, stuff) do
      [bread] ++ stuff ++ [bread]
    end
  end

  test "big hoc test" do
    Chorex.start(TestChor4.Chorex, %{Alice => MyAlice4, Bob => MyBob4}, [false])

    assert_receive {:chorex_return, Alice,
                    [
                      "Italian herbs and cheese",
                      "ham",
                      "swiss_cheese",
                      "tomato",
                      "Italian herbs and cheese"
                    ]}
  end
end

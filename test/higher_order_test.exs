defmodule HigherOrderTest do
  use ExUnit.Case
  import Chorex

  defmodule TestChor3 do
    defchor [Buyer3, Contributor3, Seller3] do
      def bookseller(decision_func) do
        Buyer3.get_book_title() ~> Seller3.(the_book)

        with Buyer3.(decision) <- decision_func.(Seller3.get_price("book:" <> the_book)) do
          if Buyer3.(decision) do
            Buyer3[L] ~> Seller3
            Buyer3.get_address() ~> Seller3.(the_address)
            Seller3.get_delivery_date(the_book, the_address) ~> Buyer3.(d_date)
            Buyer3.(d_date)
          else
            Buyer3[R] ~> Seller3
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

      bookseller(&two_party/1)
    end
  end

  defmodule MySeller3 do
    use TestChor3.Chorex, :seller3

    def get_delivery_date(_book, _addr) do
      # IO.puts("getting delivery date for")
      ~D[2024-05-13]
    end

    def get_price("book:Das Glasperlenspiel"), do: 42
    def get_price("book:Zen and the Art of Motorcycle Maintenance"), do: 13
  end

  defmodule MyBuyer3 do
    use TestChor3.Chorex, :buyer3

    def get_book_title(), do: "Zen and the Art of Motorcycle Maintenance"
    def get_address(), do: "Maple Street"
    def get_budget(), do: 22
  end

  defmodule MyContributor3 do
    use TestChor3.Chorex, :contributor3

    def compute_contrib(price) do
      # IO.inspect(price, label: "Buyer 2 computing contribution of")
      price / 2
    end
  end

  test "3-party higher-order choreography runs" do
    ps1 = spawn(MySeller3, :init, [])
    pb1 = spawn(MyBuyer3, :init, [])
    pb2 = spawn(MyContributor3, :init, [])

    config = %{Seller3 => ps1, Buyer3 => pb1, Contributor3 => pb2, :super => self()}

    send(ps1, {:config, config})
    send(pb1, {:config, config})
    send(pb2, {:config, config})

    assert_receive {:choreography_return, Buyer3, ~D[2024-05-13]}
  end

  defmodule MySeller31 do
    use TestChor3.Chorex, :seller3

    def get_delivery_date(_book, _addr) do
      ~D[2024-05-13]
    end

    def get_price("book:Das Glasperlenspiel"), do: 42
    def get_price("book:Zen and the Art of Motorcycle Maintenance"), do: 13

    def run_choreography(impl, config) do
      Seller3.bookseller(impl, config, &Seller3.one_party/3)
    end
  end

  defmodule MyBuyer31 do
    use TestChor3.Chorex, :buyer3

    def get_book_title(), do: "Zen and the Art of Motorcycle Maintenance"
    def get_address(), do: "Maple Street"
    def get_budget(), do: 22

    def run_choreography(impl, config) do
      Buyer3.bookseller(impl, config, &Buyer3.one_party/3)
    end
  end

  test "3-party higher-order choreography runs and overrides run_choreography" do
    ps1 = spawn(MySeller31, :init, [])
    pb1 = spawn(MyBuyer31, :init, [])

    config = %{Seller3 => ps1, Buyer3 => pb1, :super => self()}

    send(ps1, {:config, config})
    send(pb1, {:config, config})

    assert_receive {:choreography_return, Buyer3, ~D[2024-05-13]}
  end

  # quote do
  #   defchor [Alice, Bob] do
  #     def big_chor(sandwich_internals) do
  #       Alice.get_bread() ~> Bob.(bread)

  #       with Bob.(ingredient_stack) <- sandwich_internals.(Alice.get_allergens()) do
  #         Bob.make_sandwich(bread, ingredient_stack) ~> Alice.(sammich)
  #         Alice.(sammich)
  #       end
  #     end

  #     def pbj(Alice.(allergens)) do
  #       if Alice.allergic_to(allergens, "peanut_butter") do
  #         Alice[L] ~> Bob
  #         Alice.plz_wash() ~> Bob.(wash_hands)
  #         Bob.dry(wash_hands)
  #         Bob.(["almond_butter", "raspberry_jam"])
  #       else
  #         Alice[R] ~> Bob
  #         Bob.(["peanut_butter", "raspberry_jam"])
  #       end
  #     end

  #     def hamncheese(Alice.(allergens)) do
  #       if Alice.allergic_to(allergens, "dairy") do
  #         Alice[L] ~> Bob
  #         Bob.(["ham", "tomato"])
  #       else
  #         Alice[R] ~> Bob
  #         Bob.(["ham", "swiss_cheese", "tomato"])
  #       end
  #     end

  #     big_chor(&pbj/1)
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

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
          Alice[L] ~> Bob
          Alice.plz_wash() ~> Bob.(wash_hands)
          Bob.dry(wash_hands)
          Bob.(["almond_butter", "raspberry_jam"])
        else
          Alice[R] ~> Bob
          Bob.(["peanut_butter", "raspberry_jam"])
        end
      end

      def hamncheese(Alice.(allergens)) do
        if Alice.allergic_to(allergens, "dairy") do
          Alice[L] ~> Bob
          Bob.(["ham", "tomato"])
        else
          Alice[R] ~> Bob
          Bob.(["ham", "swiss_cheese", "tomato"])
        end
      end

      big_chor(&pbj/1)
    end
  end

  defmodule MyAlice4 do
    use TestChor4.Chorex, :alice

    def run_choreography(impl, config) do
      Alice.big_chor(impl, config, &Alice.hamncheese/3)
    end

    def get_bread(), do: "Italian herbs and cheese"
    def get_allergens(), do: ["mushroom", "peanut_butter"]
    def allergic_to(lst, thing), do: Enum.any?(lst, fn x -> x == thing end)
    def plz_wash(), do: "purge your hands of peanuts and mushrooms!"
  end

  defmodule MyBob4 do
    use TestChor4.Chorex, :bob

    def dry(x), do: IO.puts("Ok, I cleaned my hands: #{x}")

    def make_sandwich(bread, stuff) do
      [bread] ++ stuff ++ [bread]
    end

    def run_choreography(impl, config) do
      Bob.big_chor(impl, config, &Bob.hamncheese/3)
    end
  end

  test "higher-order choreography runs with custom run_choreography function" do
    alice = spawn(MyAlice4, :init, [])
    bob = spawn(MyBob4, :init, [])

    config = %{Alice => alice, Bob => bob, :super => self()}

    send(alice, {:config, config})
    send(bob, {:config, config})

    assert_receive {:choreography_return, Alice,
                    [
                      "Italian herbs and cheese",
                      "ham",
                      "swiss_cheese",
                      "tomato",
                      "Italian herbs and cheese"
                    ]}
  end
end

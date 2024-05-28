defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # quote do
  #   defchor [Buyer, Seller] do
  #     Buyer.get_book_title() ~> Seller.b
  #     Seller.get_price("foo" <> b) ~> Buyer.p
  #     Seller.(2 * 3) ~> Buyer.q
  #     Buyer.(p + 2)
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # # |> IO.inspect()
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule TestChor do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.b
      Seller.get_price("book:" <> b) ~> Buyer.p
      # Seller.get_price(b) ~> Buyer.p
      Buyer.(p + 2)
    end
  end

  defmodule MyBuyer do
    use TestChor.Chorex, :buyer

    def get_book_title(), do: "Das Glasperlenspiel"
  end

  defmodule MySeller do
    use TestChor.Chorex, :seller

    def get_price("book:Das Glasperlenspiel"), do: 40
    def get_price("Das Glasperlenspiel"), do: 39
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

    assert_receive {:choreography_return, Seller, 40}
    assert_receive {:choreography_return, Buyer, 42}
  end

  #
  # More complex choreographies
  #

  # quote do
  #   defchor [Buyer1, Buyer2, Seller1] do
  #     Buyer1.get_book_title() ~> Seller1.b
  #     Seller1.get_price("book:" <> b) ~> Buyer1.p
  #     Seller1.get_price("book:" <> b) ~> Buyer2.p
  #     # Buyer2.(p / 2) ~> Buyer1.contrib
  #     Buyer2.compute_contrib(p) ~> Buyer1.contrib

  #     if Buyer1.(p - contrib < get_budget()) do
  #       Buyer1[L] ~> Seller1
  #       Buyer1.get_address() ~> Seller1.addr
  #       Seller1.get_delivery_date(b, addr) ~> Buyer1.d_date
  #       Buyer1.d_date
  #     else
  #       Buyer1[R] ~> Seller1
  #       Buyer1.(nil)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

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
        Seller1.get_delivery_date(b, addr) ~> Buyer1.d_date
        Buyer1.d_date
      else
        Buyer1[R] ~> Seller1
        Buyer1.(nil)
      end
    end
  end

  defmodule MySeller1 do
    use TestChor2.Chorex, :seller1

    def get_delivery_date(_book, _addr) do
      # IO.puts("getting delivery date for")
      ~D[2024-05-13]
    end

    def get_price("book:Das Glasperlenspiel"), do: 42
    def get_price("book:Zen and the Art of Motorcycle Maintenance"), do: 13
  end

  defmodule MyBuyer1 do
    use TestChor2.Chorex, :buyer1

    def get_book_title(), do: "Zen and the Art of Motorcycle Maintenance"
    def get_address(), do: "Maple Street"
    def get_budget(), do: 22
  end

  defmodule MyBuyer2 do
    use TestChor2.Chorex, :buyer2

    def compute_contrib(price) do
      # IO.inspect(price, label: "Buyer 2 computing contribution of")
      price / 2
    end
  end

  test "3-party choreography runs" do
    ps1 = spawn(MySeller1, :init, [])
    pb1 = spawn(MyBuyer1, :init, [])
    pb2 = spawn(MyBuyer2, :init, [])

    config = %{Seller1 => ps1, Buyer1 => pb1, Buyer2 => pb2, :super => self()}

    send(ps1, {:config, config})
    send(pb1, {:config, config})
    send(pb2, {:config, config})

    assert_receive {:choreography_return, Buyer1, ~D[2024-05-13]}
  end

  test "get local functions from code walking" do
    stx = quote do
      42 < get_answer()
    end

    assert {_, [{Alice, {:get_answer, 0}}], []} = walk_local_expr(stx, __ENV__, Alice)
  end

  test "get function from inside complex if instruction" do
    stx = quote do
      if Alice.(42 < get_answer()) do
        Alice[L] ~> Bob
        Alice.get_question() ~> Bob.question
        Bob.deep_thought(question) ~> Alice.mice
        Alice.mice
      else
        Alice[R] ~> Bob
        Alice.("How many roads must a man walk down?")
      end
    end

    {_code, behaviour_specs, _functions} = project(stx, __ENV__, Alice)
    assert [{Alice, {:get_question, 0}}, {Alice, {:get_answer, 0}}] =
      behaviour_specs |> Enum.filter(fn {a, _} -> a == Alice end)
    assert [{Bob, {:deep_thought, 1}}] =
      behaviour_specs |> Enum.filter(fn {a, _} -> a == Bob end)
  end

  test "flatten_block/1" do
    assert {:__block__, nil, [1, 2]} =
      flatten_block({:__block__, nil, [1, {:__block__, nil, [2]}]})

    assert {:__block__, nil, [1, 2, 3]} =
      flatten_block({:__block__, nil, [1, {:__block__, nil, [2]}, 3]})
  end

  #
  # Higher-order choreographies!
  #

  defmodule TestChor3 do
    defchor [Buyer3, Contributor3, Seller3] do
      def bookseller(decision_func) do
        Buyer3.get_book_title() ~> Seller3.the_book
        with Buyer3.decision <- decision_func.(Seller3.get_price("book:" <> the_book)) do
          if Buyer3.decision do
            Buyer3[L] ~> Seller3
            Buyer3.get_address() ~> Seller3.the_address
            Seller3.get_delivery_date(the_book, the_address) ~> Buyer3.d_date
            Buyer3.d_date
          else
            Buyer3[R] ~> Seller3
            Buyer3.(nil)
          end
        end
      end

      def one_party(Seller3.the_price) do
        Seller3.the_price ~> Buyer3.p
        Buyer3.(p < get_budget())
      end

      def two_party(Seller3.the_price) do
        Seller3.the_price ~> Buyer3.p
        Seller3.the_price ~> Contributor3.p
        Contributor3.compute_contrib(p) ~> Buyer3.contrib
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

  # quote do
  #   defchor [Alice, Bob] do
  #     def big_chor(sandwich_internals) do
  #       Alice.get_bread() ~> Bob.bread
  #       with Bob.ingredient_stack <- sandwich_internals.(Alice.get_allergens()) do
  #         Bob.make_sandwich(bread, ingredient_stack) ~> Alice.sammich
  #         Alice.sammich
  #       end
  #     end

  #     def pbj(Alice.allergens) do
  #       if Alice.allergic_to(allergens, "peanut_butter") do
  #         Alice[L] ~> Bob
  #         Alice.plz_wash() ~> Bob.wash_hands
  #         Alice.(["almond_butter", "raspberry_jam"])
  #       else
  #         Alice[R] ~> Bob
  #         Alice.(["peanut_butter", "raspberry_jam"])
  #       end
  #     end

  #     def hamncheese(Alice.allergens) do
  #       if Alice.allergic_to(allergens, "dairy") do
  #         Alice.(["ham", "tomato"])
  #       else
  #         Alice.(["ham", "swiss_cheese", "tomato"])
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
        Alice.get_bread() ~> Bob.bread
        with Bob.ingredient_stack <- sandwich_internals.(Alice.get_allergens()) do
          Bob.make_sandwich(bread, ingredient_stack) ~> Alice.sammich
          Alice.sammich
        end
      end

      def pbj(Alice.allergens) do
        if Alice.allergic_to(allergens, "peanut_butter") do
          Alice[L] ~> Bob
          Alice.plz_wash() ~> Bob.wash_hands
          Bob.dry(wash_hands)
          Alice.(["almond_butter", "raspberry_jam"])
        else
          Alice[R] ~> Bob
          Alice.(["peanut_butter", "raspberry_jam"])
        end
      end

      def hamncheese(Alice.allergens) do
        if Alice.allergic_to(allergens, "dairy") do
          Alice.(["ham", "tomato"])
        else
          Alice.(["ham", "swiss_cheese", "tomato"])
        end
      end

      big_chor(&pbj/1)
    end
  end

  defmodule MyAlice4 do
    use TestChor4.Chorex, :alice

    def run_choreography(impl, config) do
      IO.inspect(config, label: "config")
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
      IO.inspect(bread, label: "bread")
      IO.inspect(stuff, label: "stuff")
      [bread] ++ stuff ++ [bread]
    end
  end

  test "higher-order choreography runs with custom run_choreography function" do
    alice = spawn(MyAlice4, :init, [])
    bob = spawn(MyBob4, :init, [])

    config = %{Alice => alice, Bob => bob, :super => self()}

    send(alice, {:config, config})
    send(bob, {:config, config})

    assert_receive {:choreography_return, Alice, 42}
  end
end

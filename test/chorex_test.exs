defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # quote do
  #   defchor [Buyer, Seller] do
  #     Buyer.get_book_title() ~> Seller.b
  #     Seller.get_price("foo" <> b) ~> Buyer.p
  #     return(Buyer.(p + 2))
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

    assert_receive {:choreography_return, 42}
  end

  #
  # More complex choreographies
  #

  # quote do
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
        return(Buyer1.d_date)
      else
        Buyer1[R] ~> Seller1
        return(Buyer1.(nil))
      end
    end
  end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

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

    assert_receive {:choreography_return, ~D[2024-05-13]}
  end

  test "get local functions from code walking" do
    stx = quote do
      42 < get_answer()
    end

    assert {_, [{Alice, {:get_answer, 0}}]} = walk_local_expr(stx, __ENV__, Alice)
  end

  test "get function from inside complex if instruction" do
    stx = quote do
      if Alice.(42 < get_answer()) do
        Alice[L] ~> Bob
        Alice.get_question() ~> Bob.question
        Bob.deep_thought(question) ~> Alice.mice
        return(Alice.mice)
      else
        Alice[R] ~> Bob
        return(Alice.("How many roads must a man walk down?"))
      end
    end

    {_code, behaviour_specs} = project(stx, __ENV__, Alice)
    assert [{Alice, {:get_question, 0}}, {Alice, {:get_answer, 0}}] =
      behaviour_specs |> Enum.filter(fn {a, _} -> a == Alice end)
    assert [{Bob, {:deep_thought, 1}}] =
      behaviour_specs |> Enum.filter(fn {a, _} -> a == Bob end)
  end

  defmodule TestChor3 do
	defchor [Buyer3, Contributor3, Seller3] do
      def bookseller(decision_func) do
        Buyer3.get_book_title() ~> Seller3.the_book
        with Buyer3.decision <- decision_func(Seller3.get_price("book:" <> the_book)) do
          if Buyer3.decision do
            Buyer3[L] ~> Seller3
            Buyer3.get_address() ~> Seller3.the_address
            Seller3.get_deliverty_date(the_book, the_address) ~> Buyer3.d_date
            return(Buyer3.d_date)
          else
            Buyer3[R] ~> Seller3
            return(Buyer3.(nil))
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
        Contributor3.(p / 2) ~> Buyer3.contrib
        Buyer3.(p - contrib < get_budget())
      end
    end
  end
end

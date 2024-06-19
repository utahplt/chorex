defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # quote do
  #   defchor [Buyer, Seller] do
  #     Buyer.get_book_title() ~> Seller.(b)
  #     Seller.get_price("foo" <> b) ~> Buyer.(p)
  #     Seller.(2 * 3) ~> Buyer.(q)
  #     Buyer.(p + 2)
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # # |> IO.inspect()
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule TestChor do
    defchor [Buyer, Seller] do
      Buyer.get_book_title() ~> Seller.(b)
      Seller.get_price("book:" <> b) ~> Buyer.(p)
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

    assert_receive {:chorex_return, Seller, 40}
    assert_receive {:chorex_return, Buyer, 42}
  end

  #
  # More complex choreographies
  #

  # quote do
  #   defchor [Buyer1, Buyer2, Seller1] do
  #     Buyer1.get_book_title() ~> Seller1.(b)
  #     Seller1.get_price("book:" <> b) ~> Buyer1.(p)
  #     Seller1.get_price("book:" <> b) ~> Buyer2.(p)
  #     # Buyer2.(p / 2) ~> Buyer1.contrib
  #     Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

  #     if Buyer1.(p - contrib < get_budget()) do
  #       Buyer1[L] ~> Seller1
  #       Buyer1.get_address() ~> Seller1.(addr)
  #       Seller1.get_delivery_date(b, addr) ~> Buyer1.(d_date)
  #       Buyer1.(d_date)
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
      Buyer1.get_book_title() ~> Seller1.(b)
      Seller1.get_price("book:" <> b) ~> Buyer1.(p)
      Seller1.get_price("book:" <> b) ~> Buyer2.(p)
      Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

      if Buyer1.(p - contrib < get_budget()) do
        Buyer1[L] ~> Seller1
        Buyer1.get_address() ~> Seller1.(addr)
        Seller1.get_delivery_date(b, addr) ~> Buyer1.(d_date)
        Buyer1.(d_date)
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

    assert_receive {:chorex_return, Buyer1, ~D[2024-05-13]}
  end

  test "get local functions from code walking" do
    stx =
      quote do
        42 < get_answer()
      end

    assert {_, [{Alice, {:get_answer, 0}}], []} = walk_local_expr(stx, __ENV__, Alice, empty_ctx())
  end

  test "get function from inside complex if instruction" do
    stx =
      quote do
        if Alice.(42 < get_answer()) do
          Alice[L] ~> Bob
          Alice.get_question() ~> Bob.(question)
          Bob.deep_thought(question) ~> Alice.(mice)
          Alice.(mice)
        else
          Alice[R] ~> Bob
          Alice.("How many roads must a man walk down?")
        end
      end

    {_code, behaviour_specs, _functions} = project(stx, __ENV__, Alice, empty_ctx())

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

  test "no behaviour code emitted when actor has no functions to implement" do
    {_result, diags} =
      Code.with_diagnostics(fn ->
        Code.compile_file("test/non_behaviour_example.ex")
      end)

    assert [] = diags
  end
end

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
    # defchor [Buyer, Seller] do
    #   Buyer.get_book_title() ~> Seller.b
    #   Seller.get_price(b) ~> Buyer.zoop
    #   return(Buyer.zoop)
    # end

    defmodule Chorex do
      (
        def buyer do
          IO.inspect("here1")

          quote do
            import Chorex.Buyer
            @behaviour Chorex.Buyer
            def init() do
              Chorex.Buyer.init(__MODULE__)
            end
          end
        end

        defmodule Buyer do
          @callback get_book_title() :: any()
          def init(impl) do
            receive do
              {:config, config} -> run_choreography(impl, config)
            end
          end

          def run_choreography(impl, config) do
            IO.inspect("go! (buyer)")
            send(config[Seller], impl.get_book_title())

            IO.inspect("waiting (buyer)")

            zoop =
              receive do
              msg -> msg
            end

            IO.inspect("got it (buyer)")

            IO.inspect(zoop, label: "zoop")
          end
        end
      )

      (
        def seller do
          IO.inspect("here1")

          quote do
            import Chorex.Seller
            @behaviour Chorex.Seller
            def init() do
              Chorex.Seller.init(__MODULE__)
            end
          end
        end

        defmodule Seller do
          @callback get_price(any()) :: any()
          def init(impl) do
            receive do
              {:config, config} -> run_choreography(impl, config)
            end
          end

          def run_choreography(impl, config) do
            IO.inspect("go! (seller)")
            b =
              receive do
              msg -> msg
            end

            send(config[Buyer], impl.get_price(b))
            nil
          end
        end
      )

      defmacro __using__(which) do
        IO.inspect(which, label: "[__using__] which ")
        apply(__MODULE__, which, [])
      end
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

    send(ps, {:config, config})
    send(pb, {:config, config})
  end
end

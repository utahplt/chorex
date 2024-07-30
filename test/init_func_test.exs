defmodule InitFuncTest do
  use ExUnit.Case
  import Chorex

  # quote do
  #   defchor [StarterAlice, StarterBob, StarterEve] do
  #     def sell_book(decision_process) do
  #       StarterAlice.get_book_title() ~> StarterEve.(the_book)

  #       with StarterAlice.(want_book?) <- decision_process.(StarterEve.get_price(the_book)) do
  #         if StarterAlice.(want_book?) do
  #           StarterAlice[L] ~> StarterEve
  #           StarterAlice.get_address() ~> StarterEve.(the_address)
  #           StarterEve.get_shipping(the_book, the_address) ~> StarterAlice.(delivery_date)
  #           StarterAlice.(delivery_date)
  #         else
  #           StarterAlice[R] ~> StarterEve
  #           StarterAlice.(nil)
  #         end
  #       end
  #     end

  #     def one_party(StarterEve.(the_price)) do
  #       StarterEve.(the_price) ~> StarterAlice.(full_price)
  #       StarterAlice.(full_price < get_budget())
  #     end

  #     def two_party(StarterEve.(the_price)) do
  #       StarterEve.(the_price) ~> StarterAlice.(full_price)
  #       StarterEve.(the_price) ~> StarterBob.(full_price)
  #       StarterBob.(full_price / 2) ~> StarterAlice.(contrib)
  #       StarterAlice.((full_price - contrib) < get_budget())
  #     end

  #     # def run(StarterAlice.(involve_bob?), StarterAlice.(budget)) do
  #     def run(StarterAlice.(involve_bob?)) do
  #       if StarterAlice.(involve_bob?) do
  #         StarterAlice[L] ~> StarterEve
  #         StarterAlice[L] ~> StarterBob
  #         sell_book(&two_party/1)
  #       else
  #         StarterAlice[R] ~> StarterEve
  #         StarterAlice[R] ~> StarterBob
  #         sell_book(&one_party/1)
  #       end
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule StarterChor do
    # defchor [StarterAlice, StarterBob, {StarterEve, :singleton}] do
    defchor [StarterAlice, StarterBob, StarterEve] do
      def sell_book(decision_process) do
        StarterAlice.get_book_title() ~> StarterEve.(the_book)

        with StarterAlice.({want_book?, my_cost}) <-
               decision_process.(StarterEve.get_price(the_book)) do
          if StarterAlice.(want_book?) do
            StarterAlice[L] ~> StarterEve
            StarterAlice.get_address() ~> StarterEve.(the_address)
            StarterEve.get_shipping(the_book, the_address) ~> StarterAlice.(delivery_date)
            StarterAlice.({delivery_date, my_cost})
          else
            StarterAlice[R] ~> StarterEve
            StarterAlice.(nil)
          end
        end
      end

      def one_party(StarterEve.(the_price)) do
        StarterEve.(the_price) ~> StarterAlice.(full_price)
        StarterAlice.({full_price < get_budget(), full_price})
      end

      def two_party(StarterEve.(the_price)) do
        StarterEve.(the_price) ~> StarterAlice.(full_price)
        StarterEve.(the_price) ~> StarterBob.(full_price)
        StarterBob.(full_price / 2) ~> StarterAlice.(contrib)

        with StarterAlice.(my_price) <- StarterAlice.(full_price - contrib) do
          StarterAlice.({my_price < get_budget(), my_price})
        end
      end

      # def run(StarterAlice.(involve_bob?), StarterAlice.(budget)) do
      def run(StarterAlice.(involve_bob?)) do
        if StarterAlice.(involve_bob?) do
          StarterAlice[L] ~> StarterEve
          StarterAlice[L] ~> StarterBob
          sell_book(&two_party/1)
        else
          StarterAlice[R] ~> StarterEve
          StarterAlice[R] ~> StarterBob
          sell_book(&one_party/1)
        end
      end
    end
  end

  defmodule StarterAliceImpl do
    use StarterChor.Chorex, :starteralice

    def get_book_title(), do: "Amusing Ourselves to Death"
    def get_address(), do: "123 San Seriffe"
    def get_budget(), do: 42
  end

  defmodule StarterEveImpl do
    use StarterChor.Chorex, :startereve

    def get_price(_), do: 25
    def get_shipping(_book, _addr), do: "next week"
  end

  defmodule StarterBobImpl do
    use StarterChor.Chorex, :starterbob
  end

  test "startup with run function works" do
    Chorex.start(
      StarterChor.Chorex,
      %{
        StarterAlice => StarterAliceImpl,
        StarterEve => StarterEveImpl,
        StarterBob => StarterBobImpl
      },
      [false]
    )

    assert_receive {:chorex_return, StarterAlice, {"next week", 25}}
  end

  test "startup with different arguments does what's expected" do
    Chorex.start(
      StarterChor.Chorex,
      %{
        StarterAlice => StarterAliceImpl,
        StarterEve => StarterEveImpl,
        StarterBob => StarterBobImpl
      },
      [true]
    )

    assert_receive {:chorex_return, StarterAlice, {"next week", 12.5}}
  end
end

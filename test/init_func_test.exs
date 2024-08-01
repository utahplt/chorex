defmodule InitFuncTest do
  use ExUnit.Case
  import Chorex

  defmodule StarterChor do
    defchor [StAlice, StBob, StEve] do
      def sell_book(decision_process, StAlice.(budget)) do
        StAlice.get_book_title() ~> StEve.(the_book)

        with StAlice.({want_book?, my_cost}) <-
               decision_process.(StEve.get_price(the_book), StAlice.(budget)) do
          if StAlice.(want_book?) do
            StAlice[L] ~> StEve
            StAlice.get_address() ~> StEve.(the_address)
            StEve.get_shipping(the_book, the_address) ~> StAlice.(delivery_date)
            StAlice.({delivery_date, my_cost})
          else
            StAlice[R] ~> StEve
            StAlice.(:too_expensive)
          end
        end
      end

      def one_party(StEve.(the_price), StAlice.(budget)) do
        StEve.(the_price) ~> StAlice.(full_price)
        StAlice.({full_price < budget, full_price})
      end

      def two_party(StEve.(the_price), StAlice.(budget)) do
        StEve.(the_price) ~> StAlice.(full_price)
        StEve.(the_price) ~> StBob.(full_price)
        StBob.(full_price / 2) ~> StAlice.(contrib)

        with StAlice.(my_price) <- StAlice.(full_price - contrib) do
          StAlice.({my_price < budget, my_price})
        end
      end

      def run(StAlice.(involve_bob?), StAlice.(budget)) do
        if StAlice.(involve_bob?) do
          StAlice[L] ~> StEve
          StAlice[L] ~> StBob
          sell_book(@two_party/2, StAlice.(budget))
        else
          StAlice[R] ~> StEve
          StAlice[R] ~> StBob
          sell_book(@one_party/2, StAlice.(budget))
        end
      end
    end
  end

  defmodule StAliceImpl do
    use StarterChor.Chorex, :stalice

    def get_book_title(), do: "Amusing Ourselves to Death"
    def get_address(), do: "123 San Seriffe"
  end

  defmodule StEveImpl do
    use StarterChor.Chorex, :steve

    def get_price(_), do: 25
    def get_shipping(_book, _addr), do: "next week"
  end

  defmodule StBobImpl do
    use StarterChor.Chorex, :stbob
  end

  test "startup with run function works" do
    Chorex.start(
      StarterChor.Chorex,
      %{
        StAlice => StAliceImpl,
        StEve => StEveImpl,
        StBob => StBobImpl
      },
      [false, 42]
    )

    assert_receive {:chorex_return, StAlice, {"next week", 25}}
  end

  test "startup with different arguments does what's expected" do
    Chorex.start(
      StarterChor.Chorex,
      %{
        StAlice => StAliceImpl,
        StEve => StEveImpl,
        StBob => StBobImpl
      },
      [true, 42]
    )

    assert_receive {:chorex_return, StAlice, {"next week", 12.5}}

    Chorex.start(
      StarterChor.Chorex,
      %{
        StAlice => StAliceImpl,
        StEve => StEveImpl,
        StBob => StBobImpl
      },
      [true, 2]
    )

    assert_receive {:chorex_return, StAlice, :too_expensive}
  end
end

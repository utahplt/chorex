defmodule InitFuncTest do
  use ExUnit.Case
  import Chorex

  quote do
    defchor [Alice, Bob, Eve] do
      def sell_book(decision_process) do
        Alice.get_book_title() ~> Eve.(the_book)

        with Alice.(want_book?) <- decision_process.(Eve.get_price(the_book)) do
          if Alice.(want_book?) do
            Alice[L] ~> Eve
            Alice.get_address() ~> Eve.(the_address)
            Eve.get_shipping(the_book, the_address) ~> Alice.(delivery_date)
            Alice.(delivery_date)
          else
            Alice[R] ~> Eve
            Alice.(nil)
          end
        end
      end

      def one_party(Eve.(the_price)) do
        Eve.(the_price) ~> Alice.(full_price)
        Alice.(full_price < get_budget())
      end

      def two_party(Eve.(the_price)) do
        Eve.(the_price) ~> Alice.(full_price)
        Eve.(the_price) ~> Bob.(full_price)
        Bob.(full_price / 2) ~> Alice.(contrib)
        Alice.((full_price - contrib) < get_budget())
      end

      # def run(Alice.(involve_bob?), Alice.(budget)) do
      def run(Alice.(involve_bob?)) do
        if Alice.(involve_bob?) do
          Alice[L] ~> Eve
          Alice[L] ~> Bob
          sell_book(&two_party/1)
        else
          Alice[R] ~> Eve
          Alice[R] ~> Bob
          sell_book(&one_party/1)
        end
      end
    end
  end
  |> Macro.expand_once(__ENV__)
  |> Macro.to_string()
  |> IO.puts()

  # defmodule StarterChor do
  #   # defchor [Alice, Bob, {Eve, :singleton}] do
  #   defchor [Alice, Bob, Eve] do
  #     def sell_book(decision_process) do
  #       Alice.get_book_title() ~> Eve.(the_book)

  #       with Alice.(want_book?) <- decision_process.(Eve.get_price(the_book)) do
  #         if Alice.(want_book?) do
  #           Alice[L] ~> Eve
  #           Alice.get_address() ~> Eve.(the_address)
  #           Eve.get_shipping(the_book, the_address) ~> Alice.(delivery_date)
  #           Alice.(delivery_date)
  #         else
  #           Alice[R] ~> Eve
  #           Alice.(nil)
  #         end
  #       end
  #     end

  #     def one_party(Eve.(the_price)) do
  #       Eve.(the_price) ~> Alice.(full_price)
  #       Alice.(full_price < get_budget())
  #     end

  #     def two_party(Eve.(the_price)) do
  #       Eve.(the_price) ~> Alice.(full_price)
  #       Eve.(the_price) ~> Bob.(full_price)
  #       Bob.(full_price / 2) ~> Alice.(contrib)
  #       Alice.((full_price - contrib) < get_budget())
  #     end

  #     # def run(Alice.(involve_bob?), Alice.(budget)) do
  #     def run(Alice.(involve_bob?)) do
  #       if Alice.(involve_bob?) do
  #         Alice[L] ~> Eve
  #         Alice[L] ~> Bob
  #         sell_book(&two_party/1)
  #       else
  #         Alice[R] ~> Eve
  #         Alice[R] ~> Bob
  #         sell_book(&one_party/1)
  #       end
  #     end
  #   end
  # end
end

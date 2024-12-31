defmodule TcoTest do
  use ExUnit.Case
  import Chorex

  # quote do
  #   defchor [CounterServer, CounterClient] do
  #     def loop(CounterServer.(i)) do
  #       if CounterClient.continue?() do
  #         CounterClient[L] ~> CounterServer
  #         CounterClient.bump() ~> CounterServer.(incr_amt)
  #         loop(CounterServer.(incr_amt + i))
  #       else
  #         CounterClient[R] ~> CounterServer
  #         CounterServer.(i) ~> CounterClient.(final_result)
  #         CounterClient.(final_result)
  #       end
  #     end

  #     def run() do
  #       loop(CounterServer.(0))
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()
end

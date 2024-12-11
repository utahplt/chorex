defmodule SmolIfTest do
  use ExUnit.Case
  import Chorex

  test "projecting irrelevant if block" do
    stx =
      quote do
        def run() do
          if Buyer1.(42) do
            Buyer1[L] ~> Seller1
            Buyer1.get_address() ~> Seller1.(addr)
          else
            Buyer1[R] ~> Seller1
            Buyer1.(:right)
            Seller1.(:right)
          end
        end
      end

    assert {{:__block__, [], []}, _, _} = project(stx, __ENV__, Buyer2, empty_ctx(__ENV__))
    # |> Macro.to_string()
    # |> IO.puts()
  end

  test "smoler test" do
    stx =
      {:__block__, [],
       [
         {:~>, [],
          [
            {{:., [from_brackets: true], [Access, :get]}, [from_brackets: true],
             [
               {:__aliases__, [alias: false], [:Buyer1]},
               {:__aliases__, [alias: false], [:L]}
             ]},
            {:__aliases__, [alias: false], [:Seller1]}
          ]},
         {:~>, [],
          [
            {{:., [], [{:__aliases__, [alias: false], [:Buyer1]}, :get_address]}, [], []},
            {{:., [], [{:__aliases__, [alias: false], [:Seller1]}]}, [],
             [{:addr, [], SmolIfTest}]}
          ]}
       ]}
    # IO.puts(Macro.to_string(stx))

    assert {_code, _funcs, _etc} = project(stx, __ENV__, Buyer2, empty_ctx(__ENV__))
    # code |> Macro.to_string() |> IO.puts()
    # |> IO.inspect(label: "final projection")
  end
end

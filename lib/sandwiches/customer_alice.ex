defmodule CustomerAlice do
  import Customer
  @behaviour Customer

  def init() do
    Customer.init(__MODULE__)
  end

  def allergic_to([:peanut], ingredients),
    do: [:peanut, :peanut_butter] |> Enum.any?(&Enum.member?(ingredients, &1))

  def get_allergens(), do: [:peanut]

  def plz_wash(), do: :just_DO_IT

  def get_bread(), do: :wheat

  def run_choreography(impl, config) do
    choice = IO.gets("pbj or ham? ")
    case IO.gets("pbj or ham? ") do
	  "pbj"  -> big_chor(impl, config, &pbj/3)
	  "ham"  -> big_chor(impl, config, &hamncheese/3)
      _      -> {:error, "bad choice!"}
    end
  end
end

defmodule Customer do
  @callback allergic_to(any(), any()) :: any()
  @callback plz_wash() :: any()
  @callback allergic_to(any(), any()) :: any()
  @callback get_allergens() :: any()
  @callback get_bread() :: any()

  def init(impl) do
    receive do
      {:config, config} ->
        ret = run_choreography(impl, config)
        send(config[:super], {:choreography_return, Customer, ret})
    end
  end

  def big_chor(impl, config, sandwich_internals) do
    chorex_send(config[StoreProxy], impl.get_bread())

    with _ <- sandwich_internals.(impl, config, impl.get_allergens()) do
      sammich =
        receive do
          msg -> msg
        end

      sammich
    end
  end

  def pbj(impl, config, allergens) do
    if impl.allergic_to(allergens, ["peanut_butter"]) do
      chorex_send(config[StoreProxy], {:choice, Customer, L})
      chorex_send(config[StoreProxy], impl.plz_wash())
      ["almond_butter", "raspberry_jam"]
    else
      chorex_send(config[StoreProxy], {:choice, Customer, R})
      ["peanut_butter", "raspberry_jam"]
    end
  end

  def hamncheese(impl, config, allergens) do
    if impl.allergic_to(allergens, ["dairy"]) do
      chorex_send(config[StoreProxy], {:choice, Customer, L})
      ["ham", "tomato"]
    else
      chorex_send(config[StoreProxy], {:choice, Customer, R})
      ["ham", "swiss_cheese", "tomato"]
    end
  end

  def chorex_send(pid, msg), do: send(pid, {:chorex, self(), msg})

  def run_choreography(impl, config) do
    if function_exported?(impl, :run_choreography, 2) do
      impl.run_choreography(impl, config)
    else
      big_chor(impl, config, &pbj/3)
    end
  end
end

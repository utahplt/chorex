defmodule Chorex do
  @moduledoc """
  Make your modules dance.

  ```elixir
  defchor ThreePartySeller(Buyer1, Buyer2, Seller) do
    Buyer1.get_book_title() -> Seller.b
    Seller.get_price(b) -> Buyer1.p
    Seller.get_price(b) -> Buyer2.p
    Buyer2.(p/2) -> Buyer1.contrib

    if Buyer1.(p - contrib < budget) do
      Buyer1[Buy] -> Seller
      Buyer1.address -> Seller.addr
      Seller.get_delivery(b, addr) -> Buyer1.d_date
      Buyer1.return(d_date)
    else
      Buyer1[NoBuy] -> Seller
      Buyer1.return(nil)
    end
  end
  ```

  Elsewhere, use like so:

  ```elixir
  defmodule Buyer1 do
    use ThreePartySeller, Buyer1

    @impl true
    def get_book_title(), do: ...

    ...
  end

  defmodule Seller do
    use ThreePartySeller, Seller

    @impl true
    def get_price(book_name), do: ...

    ...
  end

  defmodule Buyer2 do
    use ThreePartySeller, Buyer2
  end
  ```
  """

  @doc """
  Define a new choreography.
  """
  defmacro defchor({chor_name, _meta, arglist}, do: block) do
    # Am I stripping off all the hygiene mechanisms here? It'd be
    # awesome if we can ensure that the names provided by the user are
    # hygienic so that a choreography can compose with other
    # metaprogrammings!
    actors = for {:__aliases__, _meta, [name]} <- arglist, do: name
    IO.inspect(actors, label: "actors")
    quote do
      42
    end
  end

  @doc """
  Perform endpoint projection in the context of node `label`.
  """
  def project(code, label) do
    42
  end
end

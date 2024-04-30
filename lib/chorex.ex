defmodule Chorex do
  @moduledoc """
  Make your modules dance.

  ```elixir
  defchor ThreePartySeller(Buyer1, Buyer2, Seller) do
    Buyer1.get_book_title() ~> Seller.b
    Seller.get_price(b) ~> Buyer1.p
    Seller.get_price(b) ~> Buyer2.p
    Buyer2.(p/2) ~> Buyer1.contrib

    if Buyer1.(p - contrib < budget) do
      Buyer1[Buy] ~> Seller
      Buyer1.address ~> Seller.addr
      Seller.get_delivery(b, addr) ~> Buyer1.d_date
      return(Buyer1.d_date)
    else
      Buyer1[NoBuy] ~> Seller
      return(nil)
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
    projections = for {actor, {code, behaviors}} <- Enum.map(actors, &{&1, project(block, &1)}) do
      modname = Module.concat(__MODULE__, actor)
      inner_func_body = quote do
        import unquote(modname)
        @behaviour unquote(modname)
      end

      # since unquoting deep inside nested templates doesn't work so
      # well, we have to construct the AST ourselves'
      # FIXME: might need to use Macro.escape
      func_body = {:quote, [], [[do: inner_func_body]]}

      quote do
        def unquote(actor) do
          IO.inspect(unquote(actor), label: "using actor #{unquote(actor)}")
          unquote(func_body)
        end

        defmodule unquote(actor) do
          unquote_splicing(behaviors)
          unquote(code)
        end
      end
    end

    quote do
      unquote_splicing(projections)

      defmacro __using__(which) when is_atom(which) do
        apply(__MODULE__, which, [])
      end
    end
  end

  # def test do
  #   actor = Buyer1
  #   modname = Module.concat(__MODULE__, actor)
  #   func_body = quote do
  #     import unquote(modname)
  #     @behaviour unquote(modname)
  #   end

  #   body = {:quote, [], [[do: func_body]]}

  #   quote do
  #     def unquote(actor) do
  #       unquote(body)
  #     end
  #   end
  # end

  # def test2 do
  #   quote do
  #     def Buyer1 do
  #       quote do
  #         import Chorex.Buyer1
  #         @behaviour Chorex.Buyer1
  #       end
  #     end
  #   end
  # end

  @doc """
  Perform endpoint projection in the context of node `label`.

  This returns a pair of a projection for the label, and a list of
  behaviors that an implementer of the label must implement.
  """
  @spec project(term(), atom()) :: {any(), [any()]}
  def project(code, label) do
    {42, []}
  end
end

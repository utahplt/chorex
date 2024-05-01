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

  import WriterMonad

  @doc """
  Define a new choreography.
  """
  defmacro defchor({chor_name, _meta, arglist}, do: block) do
    # Am I stripping off all the hygiene mechanisms here? It'd be
    # awesome if we can ensure that the names provided by the user are
    # hygienic so that a choreography can compose with other
    # metaprogrammings!
    actors = arglist |> Enum.map(&Macro.expand_once(&1, __CALLER__))
    projections = for {actor, {code, behaviors}} <- Enum.map(actors,
                        &{&1, project(block, __CALLER__, &1)}) do
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

  def test do
    code = quote do
      defchor selling(Buyer, Seller) do
        Buyer.get_book_title() ~> Seller.b
        Seller.get_price(b) ~> Buyer.p
        return(Buyer1.p)
      end
    end
    code
    |> Macro.expand_once(__ENV__)
    |> Macro.to_string()
    |> IO.puts
  end

  defmodule ProjectionError do
    defexception message: "unable to project"
  end

  @doc """
  Perform endpoint projection in the context of node `label`.

  This returns a pair of a projection for the label, and a list of
  behaviors that an implementer of the label must implement.
  """
  @spec project(term(), Macro.Env.t(), atom()) :: {any(), [any()]}
  def project({:__block__, meta, terms}, env, label) do
    mapM(&project(&1, env, label), terms)
    ~>> &return({:__block__, meta, &1})
  end

  def project({:~>, meta, [{party1, _m1, args1}, {party2, _m2, args2}]}, env, label) do
    {:., _, [hd1, tl1]} = party1
    {:., _, [hd2, tl2]} = party2
    actor1 = Macro.expand_once(hd1, env)
    actor2 = Macro.expand_once(hd2, env)

    case {actor1, actor2} do
      {^label, ^label} -> raise ProjectionError, message: "Can't project sending self a message"
      {^label, _} ->
        {quote do
          # FIXME: how do I send this to to the right process concretely?
          # I'll probably need some kind of registry or something that
          # looks up the right variables.
          send(lookup_pid(unquote(actor2)), unquote(tl1))
        end, []}
      {_, ^label} ->
        {quote do
          # FIXME: how do I send this to to the right process concretely?
          # I'll probably need some kind of registry or something that
          # looks up the right variables.
          # unquote(tl2) = receive, do: m -> m
          unquote(tl2) = receive do
            msg -> msg
          end
        end, []}
      {_, _} ->                 # Not a party to this communication
        return(quote do end)
    end
  end

  def project({:return, _meta, [{{:., _, [actor_alias, var_or_func]}, _, _maybe_args}]}, env, label) do
    actor = Macro.expand_once(actor_alias, env)
    case actor do
      ^label -> return(var_or_func)
      _ -> return(quote do end)
    end
  end

  def project(code, _env, _label) do
    IO.inspect(code, label: "unrecognized code")
    return(42)
  end
end

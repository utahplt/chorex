defmodule Chorex do
  @moduledoc """
  Make your modules dance.

  ```elixir
  defmodule ThreePartySeller do
    defchor (Buyer1, Buyer2, Seller) do
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
  end
  ```

  Elsewhere, use like so:

  ```elixir
  defmodule Buyer1 do
  use ThreePartySeller.Chor, Buyer1

  @impl true
  def get_book_title(), do: ...

  ...
  end

  defmodule Seller do
  use ThreePartySeller.Chor, Seller

  @impl true
  def get_price(book_name), do: ...

  ...
  end

  defmodule Buyer2 do
  use ThreePartySeller.Chor, Buyer2
  end
  ```
  """

  import WriterMonad
  import Utils

  @doc """
  Define a new choreography.
  """
  defmacro defchor(arglist, do: block) do
    # Am I stripping off all the hygiene mechanisms here? It'd be
    # awesome if we can ensure that the names provided by the user are
    # hygienic so that a choreography can compose with other
    # metaprogrammings!
    actors = arglist |> Enum.map(&Macro.expand_once(&1, __CALLER__))

    IO.inspect(actors, label: "actors")

    projections =
      for {actor, {code, callback_specs}} <-
            Enum.map(
              actors,
              &{&1, project(block, __CALLER__, &1)}
            ) do
        # Just the actor; aliases will resolve to the right thing
        modname = actor

        inner_func_body =
          quote do
            import unquote(modname)
            @behaviour unquote(modname)

            def init() do
              unquote(modname).init(__MODULE__)
            end
          end

        # since unquoting deep inside nested templates doesn't work so
        # well, we have to construct the AST ourselves'
        func_body = {:quote, [], [[do: inner_func_body]]}

        my_callbacks =
          Enum.filter(
            callback_specs,
            fn
              {^actor, _} -> true
              _ -> false
            end
          )

        callbacks =
          for {_, {name, arity}} <- my_callbacks do
            args =
              if arity == 0 do
                []
              else
                for _ <- 1..arity do
                  quote do
                    any()
                  end
                end
              end

            quote do
              @callback unquote(name)(unquote_splicing(args)) :: any()
            end
          end

        quote do
          def unquote(Macro.var(downcase_atom(actor), __CALLER__.module)) do
            IO.inspect(unquote(actor), label: "calling helper use function for")
            unquote(func_body)
          end

          defmodule unquote(actor) do
            unquote_splicing(callbacks)

            # impl is the name of a module implementing this behavior
            def init(impl) do
              receive do
                # TODO: config validation: make sure all keys for needed actors present
                {:config, config} -> run_choreography(impl, config)
              end
            end

            def run_choreography(impl, config) do
              unquote(code)
            end
          end
        end
      end

    quote do
      defmodule Chorex do
        unquote_splicing(projections)

        defmacro __using__(which) do
          IO.inspect(which, label: "[__using__] which ")
          apply(__MODULE__, which, [])
        end
      end
    end
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
    monadic do
      new_terms <- terms |> mapM(&project(&1, env, label))
      return({:__block__, meta, new_terms})
    end
  end

  def project(
        {:~>, _meta, [{party1, m1, args1}, {party2, _m2, []}]},
        env,
        label
      ) do
    {:., _, [hd1, tl1]} = party1
    {:., _, [hd2, tl2]} = party2
    actor1 = Macro.expand_once(hd1, env)
    actor2 = Macro.expand_once(hd2, env)

    {thing1, callbacks} =
      case {m1, args1} do
        {[{:no_parens, true} | _], []} ->
          {Macro.var(tl1, nil), []}

        {_, []} ->
          {quote do
             impl. unquote(tl1)()
           end, [{actor1, {tl1, 0}}]}

        {_, args} ->
          {quote do
             impl. unquote(tl1)(unquote_splicing(args))
           end, [{actor1, {tl1, length(args)}}]}
      end

    case {actor1, actor2} do
      {^label, ^label} ->
        raise ProjectionError, message: "Can't project sending self a message"

      {^label, _} ->
        {quote do
           # FIXME: how do I send this to to the right process concretely?
           # I'll probably need some kind of registry or something that
           # looks up the right variables.
           send(config[unquote(actor2)], unquote(thing1))
         end, callbacks}

      {_, ^label} ->
        rec_var = Macro.var(tl2, nil)
        {quote do
           # FIXME: how do I send this to to the right process concretely?
           # I'll probably need some kind of registry or something that
           # looks up the right variables.
           unquote(rec_var) =
             receive do
               # z = receive do
               msg -> msg
             end
         end, callbacks}

      # Not a party to this communication
      {_, _} ->
        return(
          quote do
          end
        )
    end
  end

  def project(
        {:return, _meta, [{{:., _, [actor_alias, var_or_func]}, m1, maybe_args}]},
        env,
        label
      ) do
    actor = Macro.expand_once(actor_alias, env)

    thing1 =
      case {m1, maybe_args} do
        {[{:no_parens, true} | _], []} ->
          Macro.var(var_or_func, nil)

        {_, []} ->
          quote do
            unquote(Macro.var(var_or_func, nil))()
          end

        {_, args} ->
          quote do
            unquote(Macro.var(var_or_func, nil))(unquote_splicing(args))
          end
      end

    case actor do
      ^label ->
        return(thing1)

      _ ->
        return(
          quote do
          end
        )
    end
  end

  def project(code, _env, _label) do
    IO.inspect(code, label: "unrecognized code")
    return(42)
  end
end

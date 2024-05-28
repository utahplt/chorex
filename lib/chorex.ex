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
    use ThreePartySeller.Chor, :buyer1

    @impl true
    def get_book_title(), do: ...

  ...
  end

  defmodule Seller do
    use ThreePartySeller.Chor, :seller

    @impl true
    def get_price(book_name), do: ...

  ...
  end

  defmodule Buyer2 do
    use ThreePartySeller.Chor, :buyer2
  end
  ```
  """

  import WriterMonad
  import Utils

  defguard is_immediate(x) when is_number(x) or is_atom(x) or is_binary(x)

  @doc """
  Define a new choreography.
  """
  defmacro defchor(arglist, do: block) do
    # Am I stripping off all the hygiene mechanisms here? It'd be
    # awesome if we can ensure that the names provided by the user are
    # hygienic so that a choreography can compose with other
    # metaprogrammings!
    actors = arglist |> Enum.map(&Macro.expand_once(&1, __CALLER__))

    projections =
      for {actor, {code, callback_specs, fresh_functions}} <-
            Enum.map(
              actors,
              &{&1, project(block, __CALLER__, &1)}
            ) do
        # Just the actor; aliases will resolve to the right thing
        modname = actor

        code = flatten_block(code)
        fresh_functions = for {_name, func_code} <- fresh_functions, do: func_code

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
            unquote(func_body)
          end

          defmodule unquote(actor) do
            unquote_splicing(callbacks)

            # impl is the name of a module implementing this behavior
            def init(impl) do
              receive do
                # TODO: config validation: make sure all keys for needed actors present
                {:config, config} ->
                  ret = run_choreography(impl, config)
                  send(config[:super], {:choreography_return, unquote(actor), ret})
              end
            end

            unquote_splicing(fresh_functions)

            def run_choreography(impl, config) do
              if function_exported?(impl, :run_choreography, 2) do
                impl.run_choreography(impl, config)
              else
                unquote(code)
              end
            end
          end
        end
      end

    quote do
      defmodule Chorex do
        unquote_splicing(projections)

        defmacro __using__(which) do
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
  @spec project(term(), Macro.Env.t(), atom()) :: WriterMonad.t()
  def project({:__block__, _meta, [term]}, env, label),
    do: project(term, env, label)

  def project({:__block__, _meta, terms}, env, label),
    do: project_sequence(terms, env, label)

  def project({:def, _meta, [fn_name, [do: fn_body]]}, env, label) do
    case fn_name do
      # Local functions
      {_name, _, [{{:., _, _}, _, _} | _]} ->
        project_local_func(fn_name, fn_body, env, label)

      # Global functions
      _ ->
        project_global_func(fn_name, fn_body, env, label)
    end
  end

  # Alice.e ~> Bob.x
  def project(
        {:~>, _meta, [party1, party2]},
        env,
        label
      ) do
    {:ok, actor1} = actor_from_local_exp(party1, env)
    {:ok, actor2} = actor_from_local_exp(party2, env)
    monadic do
      sender_exp <- project_local_expr(party1, env, actor1)
      recver_exp <- project_local_expr(party2, env, actor2)
      case {actor1, actor2} do
        {^label, ^label} ->
          raise ProjectionError, message: "Can't project sending self a message"

        {^label, _} ->
          return(quote do
                  send(config[unquote(actor2)], unquote(sender_exp))
          end)

        {_, ^label} ->
          # As far as I can tell, nil is the right context, because when
          # I look at `args' in the previous step, it always has context
          # nil when I'm expanding the real thing.
          return(quote do
                  unquote(recver_exp) =
                    receive do
                    msg -> msg
                  end
          end)

        # Not a party to this communication
        {_, _} ->
          mzero()
      end
    end
  end

  # if Alice.(test) do C₁ else C₂ end
  def project(
    {:if, _meta1, [tst_exp, [do: tcase, else: fcase]]},
    env,
    label
  ) do
    {:ok, actor} = actor_from_local_exp(tst_exp, env)

    monadic do
      # The test can only run on a single node
      tst <- project_local_expr(tst_exp, env, actor)
      b1 <- project_sequence(tcase, env, label)
      b2 <- project_sequence(fcase, env, label)
      if actor == label do
        quote do
          if unquote(tst) do
            unquote(b1)
          else
            unquote(b2)
          end
        end
      else
        merge(b1, b2)
      end
      |> return()
    end
  end

  # let notation, but we're using `with' syntax from Elixir
  # with Alice.var <- expr do ... end
  def project(
    {:with, _meta, [{:<-, _, [var, expr]}, [do: body]]},
    env,
    label
  ) do
    {:ok, actor} = actor_from_local_exp(var, env)
    monadic do
      var_  <- project(var, env, label)
      expr_ <- project(expr, env, label)
      body_ <- project(body, env, label)
      if actor == label do
        return(quote do
                with unquote(var_) <- unquote(expr_) do
                  unquote(body_)
                end
        end)
      else
        return(quote do
                with _ <- unquote(expr_) do
                  unquote(body_)
                end
        end)
      end
    end
  end

  # Local expressions of the form Actor.thing or Actor.(thing)
  def project({{:., _, _}, _, _} = expr, env, label) do
    project_local_expr(expr, env, label)
  end

  # Application projection
  def project({fn_name, _meta, [arg]}, env, label)
  when is_atom(fn_name) do
    with {:ok, actor} <- actor_from_local_exp(arg, env) do
      if label == actor do
        monadic do
          arg_ <- project(arg, env, label)
          return(quote do
                  unquote(fn_name)(unquote(arg_))
          end)
        end
      else
        return(quote do
                unquote(fn_name)()
        end)
      end
    else
      :error ->
        # Add two to the arity to account for impl, config
        {:&, m1, [{:/, m2, [{var_name, m3, var_ctx}, arity]}]} = arg
        arg_ = {:&, m1, [{:/, m2, [{var_name, m3, var_ctx}, arity + 2]}]}
        return(quote do
                unquote(fn_name)(impl, config, unquote(arg_))
        end)
    end
  end

  def project(code, _env, _label) do
    raise ProjectionError, message: "Unrecognized code: #{inspect code}"
  end

  #
  # Projecting sequence of statements
  #

  @spec project_sequence(term(), Macro.Env.t(), atom()) :: WriterMonad.t()
  def project_sequence(
    {:__block__, _meta, [expr]},
    env,
    label
  ) do
    project(expr, env, label)
  end

  def project_sequence(
    {:__block__, _meta, [_ | _] = exprs},
    env,
    label
  ) do
    project_sequence(exprs, env, label)
  end

  def project_sequence(         # Choice information: Alice[L] ~> Bob
    [
      {:~>, _meta,
       [{{:., [{:from_brackets, true} | _], [Access, :get]}, [{:from_brackets, true} | _],
         [
           sender_alias,
           choice_alias
         ]},
        dest_alias]} | cont],
    env,
    label
  ) do
    sender = Macro.expand_once(sender_alias, env)
    choice = Macro.expand_once(choice_alias, env)
    dest = Macro.expand_once(dest_alias, env)

    monadic do
      cont_ <- project_sequence(cont, env, label)
      case {sender, dest} do
        {^label, _} ->
          return(quote do
                  send(config[unquote(dest)], {:choice, unquote(sender), unquote(choice)})
                  unquote(cont_)
          end)
        {_, ^label} ->
          return(quote do
                  receive do
                    {:choice, unquote(sender), unquote(choice)} ->
                      unquote(cont_)
                  end
          end)
        _ ->
          mzero()
      end
    end
  end

  def project_sequence([expr], env, label) do
    project(expr, env, label)
  end

  def project_sequence([expr | cont], env, label) do
    monadic do
      expr_ <- project(expr, env, label)
      cont_ <- project_sequence(cont, env, label)
      return(quote do
              unquote(expr_)
              unquote(cont_)
      end |> flatten_block())
    end
  end

  # Handle cases where there is only one thing in a sequence
  def project_sequence(expr, env, label),
    do: project(expr, env, label)

  def project_local_func({fn_name, _, [{{:., _, [actor, var_name]}, _, []}]}, body, env, label) do
    {:ok, actor} = actor_from_local_exp(actor, env)
    var = Macro.var(var_name, nil)
    if actor == label do
      monadic do
        body_ <- project(body, env, label)
        r <- mzero()
        return(r, [], [{fn_name, quote do
                         def unquote(fn_name)(impl, config, unquote(var)) do
                           unquote(body_)
                         end
                       end}])
      end
    else
      monadic do
        body_ <- project(body, env, label)
        r <- mzero()
        return(r, [], [{fn_name, quote do
                         def unquote(fn_name)(impl, config, _input_x) do # var shouldn't be capturable
                           unquote(body_)
                         end
                       end}])
      end
    end
  end

  def project_global_func({fn_name, _, [var]}, body, env, label) do
    monadic do
      body_ <- project(body, env, label)
      r <- mzero()
      return(r, [], [{fn_name, quote do
                       def unquote(fn_name)(impl, config, unquote(var)) do
                         unquote(body_)
                       end
                     end}])
    end
  end


  #
  # Local expression handling
  #

  @doc """
  Get the actor name from an expression

  actor_from_local_exp((quote do: Foo.bar(42)), __ENV__)
  {:ok, Foo}
  """
  def actor_from_local_exp({{:., _, [actor_alias | _]}, _, _}, env),
    do: {:ok, Macro.expand_once(actor_alias, env)}

  def actor_from_local_exp({:__aliases__, _, _} = actor_alias, env),
    do: {:ok, Macro.expand_once(actor_alias, env)}

  def actor_from_local_exp(_, _), do: :error

  # Whether or not a local expression looks like a var/funcall, or if
  # it looks like an expression
  # defp local_var_or_expr?({{:., _, [_, x]}, _, _}) when is_atom(x),
  #   do: :var

  # defp local_var_or_expr?({{:., _, [_]}, _, _}),
  #   do: :expr

  @doc """
  Like `project/3`, but focus on handling `ActorName.local_var`,
  `ActorName.local_func()` or `ActorName.(local_exp)`. Handles walking
  the local expression to gather list of functions needed for the
  behaviour to implement.
  """
  def project_local_expr(        # Foo.var or Foo.func(...)
    {{:., _m0, [actor, var_or_func]}, m1, maybe_args},
    env,
    label
  ) when is_atom(var_or_func) do
    {:ok, actor} = actor_from_local_exp(actor, env)

    if actor == label do
      case Keyword.fetch(m1, :no_parens) do
        {:ok, true} ->            # Foo.var
          return(Macro.var(var_or_func, nil))

        _ -> monadic do           # Foo.func(...)
            args <- mapM(maybe_args, &walk_local_expr(&1, env, label))
            return(quote do
                    impl. unquote(var_or_func)(unquote_splicing(args))
            end, [{actor, {var_or_func, length(args)}}])
          end
      end
    else
      mzero()
    end
  end

  def project_local_expr(        # Foo.(expr)
    {{:., _m0, [actor]}, _m1, [exp]},
    env,
    label
  ) do
    with {:ok, actor} <- actor_from_local_exp(actor, env) do
      if actor == label do
        walk_local_expr(exp, env, label)
      else
        mzero()
      end
    else
      :error ->
        # No actor; treat as variable
        {var_name, _var_meta, _var_ctx} = actor
        monadic do
          exp_ <- project(exp, env, label)
          return(quote do
                  unquote(Macro.var(var_name, nil)).(impl, config, unquote(exp_))
          end)
        end
    end
  end

  def walk_local_expr(code, env, label) do
    {code, acc} = Macro.postwalk(code, [], &do_local_project_wrapper(&1, &2, env, label))
    return(code, acc)
  end

  def do_local_project_wrapper(code, acc, env, label) do
    {code_, acc_, []} = do_local_project(code, acc, env, label)
    {code_, acc_}
  end

  defp do_local_project({varname, _meta, nil} = var, acc, _env, _label) when is_atom(varname) do
    return(var, acc)
  end

  defp do_local_project({funcname, _meta, args} = funcall, acc, _env, label)
  when is_atom(funcname) and is_list(args) do
    num_args = length(args)
    builtins = Kernel.__info__(:functions) ++ Kernel.__info__(:macros)

    if Enum.member?(builtins, {funcname, num_args}) do
      return(funcall, acc)
    else
      return(quote do
              impl. unquote(funcname)(unquote_splicing(args))
      end,
        [{label, {funcname, length(args)}} | acc])
    end
  end

  defp do_local_project(x, acc, _env, _label) do
    return(x, acc)
  end

  def flatten_block({:__block__, _meta, [expr]}), do: expr
  def flatten_block({:__block__, meta, exprs}) do
    exprs
    |> Enum.map(&flatten_block/1)
    |> Enum.filter(fn {:__block__, _, []} -> false # drop empty blocks
                      _ -> true end)
    |> then(&{:__block__, meta, &1})
  end
  def flatten_block({other, meta, exprs}) when is_list(exprs),
    do: {other, meta, Enum.map(exprs, &flatten_block/1)}
  def flatten_block(other), do: other

  @doc """
  Perform the control merge function, but flatten block expressions at each step
  """
  def merge(x, x), do: x
  def merge(x, y), do: merge_step(flatten_block(x), flatten_block(y))

  def merge_step(x, x), do: x

  def merge_step(
    {:if, m1, [test, [do: tcase1, else: fcase1]]},
    {:if, _m2, [test, [do: tcase2, else: fcase2]]})
    do
    {:if, m1, [test, [do: merge(tcase1, tcase2), else: merge(fcase1, fcase2)]]}
  end

  def merge_step(
    {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, agent, L]}], l_branch]}]]]},
    {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, agent, R]}], r_branch]}]]]}
    ) do
    quote do
      receive do
        {:choice, unquote(agent), L} -> unquote(l_branch)
        {:choice, unquote(agent), R} -> unquote(r_branch)
      end
    end
  end

  def merge_step(               # flip order of branches
    {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, agent, R]}], r_branch]}]]]},
    {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, agent, L]}], l_branch]}]]]}
    ) do
    quote do
      receive do
        {:choice, unquote(agent), L} -> unquote(l_branch)
        {:choice, unquote(agent), R} -> unquote(r_branch)
      end
    end
  end

  def merge_step(               # merge same branch
    {:receive, m1, [[do: [{:->, m2, [[{:{}, m3, [:choice, agent, dir]}], branch1]}]]]},
    {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, agent, dir]}], branch2]}]]]}
    ) do
    {:receive, m1, [[do: [{:->, m2, [[{:{}, m3, [:choice, agent, dir]}], merge(branch1, branch2)]}]]]}
  end

  def merge_step(x, y) do
    raise ProjectionError, message: "Cannot merge terms:\n  term 1: #{inspect x}\n  term 2: #{inspect y}"
  end
end

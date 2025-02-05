defmodule Chorex do
  @moduledoc """
  Main projector for choreographies.
  """

  # Trace all Chorex messages
  @tron false

  alias Chorex.RuntimeMonitor

  import FreeVarAnalysis
  import WriterMonad
  import Utils

  @typedoc """
  A tuple describing where to find a remote host. The `Chorex.start/3`
  function takes this and spins up proxies as needed to manage the connection.

  ```elixir
  {:remote, listen_socket :: integer(), remote_host :: binary(), remote_port :: integer()}
  ```
  """
  @type remote_actor_ref() :: {:remote, integer(), binary(), integer()}

  @doc """
  Start a choreography.

  Takes a choreography module like `MyCoolThing.Chorex`, a map from
  actor names to implementing modules, and a list of arguments to pass
  to the `run` function.

  Values in the map are either modules or `remote_actor_ref()` tuples.

  ## Example

  ```elixir
  Chorex.start(ThreePartySeller.Chorex,
               %{ Buyer1 => MyBuyer1, Buyer2 => MyBuyer2, Seller => MySeller },
               [])
  ```
  """
  @spec start(module(), %{atom() => module() | remote_actor_ref()}, [
          any()
        ]) :: any()
  def start(chorex_module, actor_impl_map, init_args) do
    session_token = UUID.uuid4()

    {:ok, rtm} = RuntimeMonitor.start_session(session_token)

    actor_list = chorex_module.get_actors()

    for actor_desc <- actor_list do
      case actor_impl_map[actor_desc] do
        {:remote, _lport, _rhost, _rport} = spec ->
          # Spawn a proxy for the process
          {:ok, pid} = RuntimeMonitor.start_remote(rtm, actor_desc, spec)
          {actor_desc, pid}

        m when is_atom(actor_desc) ->
          # Spawn the process
          {:ok, pid} = RuntimeMonitor.start_child(rtm, actor_desc, m)
          {actor_desc, pid}
      end
    end

    RuntimeMonitor.kickoff(rtm, init_args)

    # FIXME <<__REIMPLEMENT__
    # pre_config =
    #   for actor_desc <- actor_list do
    #     case actor_impl_map[actor_desc] do
    #       {:remote, lport, rhost, rport} ->
    #         {actor_desc, {:remote, lport, rhost, rport}}

    #       m when is_atom(actor_desc) ->
    #         # Spawn the process
    #         pid = RuntimeMonitor.start_child(rtm, actor_desc, m)
    #         # ↓ Obsolete ↓
    #         # {:ok, pid} = RuntimeSupervisor.start_child(supervisor,
    #         #                                            m,
    #         #                                            {actor_desc, m, self(), session_token})
    #         # {:ok, pid} = GenServer.start_link(m, {a, m, self(), session_token})
    #         {actor_desc, pid}
    #     end
    #   end
    #   |> Enum.into(%{})

    # Gather up actors that need remote proxies
    # remotes =
    #   pre_config
    #   |> Enum.flat_map(fn
    #     {_k, {:remote, _, _, _} = r} -> [r]
    #     _ -> []
    #   end)
    #   |> Enum.into(MapSet.new())

    # remote_proxies =
    #   for {:remote, lport, rhost, rport} = proxy_desc <- remotes do
    #     {:ok, proxy_pid} =
    #       GenServer.start(Chorex.SocketProxy, %{
    #         listen_port: lport,
    #         remote_host: rhost,
    #         remote_port: rport
    #       })

    #     {proxy_desc, proxy_pid}
    #   end
    #   |> Enum.into(%{})

    # config =
    #   pre_config
    #   |> Enum.map(fn
    #     {a, {:remote, _, _, _} = r_desc} -> {a, remote_proxies[r_desc]}
    #     {a, pid} -> {a, pid}
    #   end)
    #   |> Enum.into(%{})
    #   |> Map.put(:super, self())
    #   |> Map.put(:session_token, session_token)
    #   # FIXME: the above should be handled by RuntimeMonitor

    # for actor_desc <- actor_list do
    #   case actor_desc do
    #     a when is_atom(a) ->
    #       # msg = {:chorex, session_token, :meta, {:config, config, init_args}}
    #       msg = {:config, config, init_args}
    #       send(config[a], msg)
    #   end
    # end

    # __REIMPLEMENT__
  end

  @doc """
  Define a new choreography.

  See the documentation for the `Chorex` module for more details.
  """
  defmacro defchor(actor_list, do: block) do
    actors = actor_list |> Enum.map(&expand_alias(&1, __CALLER__))

    ctx = empty_ctx(__CALLER__, actors)

    projections =
      for {actor, {naked_code, callback_specs, fresh_functions}} <-
            Enum.map(
              actors,
              fn a ->
                {a, project(block, __CALLER__, a, ctx)}
              end
            ) do
        # Just the actor; aliases will resolve to the right thing
        modname = actor

        # Warn the user if they don't have their code wrapped in `run`
        unless match?({:__block__, _, []}, flatten_block(naked_code)) do
          IO.warn("Useless code in choreography: all code must be wrapped inside a function")
        end

        fresh_functions =
          fresh_functions
          |> Enum.map(fn {_, func_code} -> func_code end)

        my_callbacks =
          Enum.filter(
            callback_specs,
            fn
              {^actor, _} -> true
              _ -> false
            end
          )
          |> Enum.sort()
          |> Enum.dedup()

        # Check: is the actor actually a behaviour? If no functions to
        # implement, don't include the '@behaviour' decl. in the module.
        behaviour_decl =
          if length(my_callbacks) > 0 do
            quote do
              @behaviour unquote(modname)
            end
          else
            quote do
            end
          end

        # Build callback declarations
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

        # Check: what functions do I need to have a defdelegate clause for?
        fun_name = fn
          {:def, _, [{:when, _, [{n, _, _} | _]} | _]} -> n
          {:def, _, [{n, _, _} | _]} -> n
        end

        delegate_decl =
          if Enum.find(fresh_functions, fn f -> fun_name.(f) == :handle_info end) do
            quote do
              defdelegate handle_info(a, b), to: unquote(modname)
            end
          else
            quote do
            end
          end

        # If we need to delegate more than :handle_info, this code can
        # be adapted to do it. We used to need :handle_continue as well.
        #
        # delegate_decl =
        #   for f <- [:handle_info],
        #       Enum.find(fresh_functions, fn fd -> fun_name.(fd) == f end) do
        #     quote do
        #       defdelegate unquote(f)(a, b), to: unquote(modname)
        #     end
        #   end

        # Innards of the auto-generated function that will be called
        # when you say "use Foo.Chorex, :actorname"
        inner_func_body =
          quote do
            # e.g. import Alice
            import unquote(modname)
            unquote(behaviour_decl)
            # mostly for state manipulating functions; needs alias below
            use Runtime

            # unquote_splicing(delegate_decl)
            # insert defdelegate handle_info(...) if needed
            unquote(delegate_decl)
            defdelegate handle_continue(a, b), to: unquote(modname)
          end

        # Since unquoting deep inside nested templates doesn't work so
        # well, we have to construct the AST ourselves
        func_body = {:quote, [], [[do: inner_func_body]]}

        quote do
          def unquote(Macro.var(downcase_atom(actor), __CALLER__.module)) do
            unquote(func_body)
          end

          defmodule unquote(actor) do
            # Need to have the alias below in the next quote block
            use Runtime
            unquote_splicing(callbacks)
            unquote_splicing(fresh_functions)
          end
        end
      end

    quote do
      # Alias needed for the "use Runtime" above
      alias Chorex.Runtime

      defmodule Chorex do
        def get_actors() do
          unquote(actor_list)
        end

        unquote_splicing(projections |> flatten_block())

        defmacro __using__(which) do
          apply(__MODULE__, which, [])
        end
      end
    end
  end

  def empty_ctx(caller, actors \\ []) do
    %{vars: [], caller: caller, actors: actors}
  end

  defp expand_alias(actor, caller) do
    Macro.expand_once(actor, caller)
  end

  defmodule CommunicationIntegrity do
    defexception message: "communication integrity violated"
  end

  defmodule ProjectionError do
    defexception message: "unable to project"
  end

  defp error_location(meta) do
    line =
      case Keyword.fetch(meta, :line) do
        {:ok, ln} -> " line #{ln}"
        _ -> ""
      end

    col =
      case Keyword.fetch(meta, :column) do
        {:ok, c} -> " column #{c}"
        _ -> ""
      end

    " at#{line}#{col}"
  end

  @doc """
  Perform endpoint projection in the context of node `label`.

  This returns a pair of a projection for the label, and a list of
  behaviors that an implementer of the label must implement.

  Arguments:

  1. Elixir AST term to project.
  2. Macro environment.
  3. Name of the actor currently under projection. Atom.
  4. Extra information about the expansion. Map. Contains:
      - vars :: set of live variables
      - actors :: list of all actor names

  Returns an instance of the `WriterMonad`, which is just a 3-tuple
  containing:

  1. The projected term. Elixir AST.
  2. A list of callback specifications for this actor. (Functions the
     actor implementer needs to have.)
  3. List of auxiliary functions generated during the projection process.

  """
  @spec project(term :: term(), env :: Macro.Env.t(), label :: atom(), ctx :: map()) ::
          WriterMonad.t()
  def project({:__block__, _meta, terms}, env, label, ctx),
    do: project_sequence(terms, env, label, ctx)

  # Function projection
  def project({:def, meta, [{fn_name, _meta2, params}, [do: body]]}, env, label, ctx) do
    body = normalize_block(body, meta)

    monadic do
      params_ <- mapM(params, &project_identifier(&1, env, label))

      body_ <-
        project_sequence(body, env, label, %{
          ctx
          | # params_ might have "_" in it when parameter not for
            # this label; do not add _ to ctx.vars
            vars: FreeVarAnalysis.extract_new_pattern_var_names(params_) ++ ctx.vars
        })

      # no return value from a function *definition*
      r <- mzero()

      with {:__block__, _, header_statements} <- function_header(ctx) do
        full_body =
          quote do
            unquote_splicing(header_statements)
            unquote(body_)
          end
          |> flatten_block()

        return_func(
          r,
          {fn_name,
           quote do
             def unquote(fn_name)(unquote_splicing(params_), state) do
               # dbg({unquote(label), :fn_called, unquote(fn_name)})
               unquote(full_body)
             end
           end}
        )
      end
    end
  end

  def project({{:., _, [{:__aliases__, _, _} | _]}, _, _} = expr, env, label, ctx) do
    project_local_expr(expr, env, label, ctx)
  end

  def project([], _env, _label, _ctx) do
    mzero()
  end

  def project({_, meta, _} = code, _env, _label, _ctx) do
    raise ProjectionError,
      message:
        "No projection#{error_location(meta)} for form: #{Macro.to_string(code)}\n   Stx: #{inspect(code)}"
  end

  #
  # Projecting sequence of statements
  #

  @doc """
  Project a sequence of expressions.
  """
  @spec project_sequence(term(), Macro.Env.t(), atom(), map()) :: WriterMonad.t()
  def project_sequence(
        [{:def, _, _} = fndef | cont],
        env,
        label,
        ctx
      ) do
    monadic do
      _whatever <- project(fndef, env, label, ctx)
      project_sequence(cont, env, label, ctx)
    end
  end

  def project_sequence(
        [{:__block__, _meta, [_ | _] = exprs} | cont],
        env,
        label,
        ctx
      ) do
    project_sequence(exprs ++ cont, env, label, ctx)
  end

  # if Alice.(test) do C₁ else C₂ end
  def project_sequence(
        [{:if, meta, [tst_exp, [do: tcase, else: fcase]]} | cont],
        env,
        label,
        ctx
      ) do
    project_sequence(
      [{:if, meta, [tst_exp, [notify: :all], [do: tcase, else: fcase]]} | cont],
      env,
      label,
      ctx
    )
  end

  def project_sequence(
        [{:if, meta, [tst_exp, [notify: notify_list], [do: tcase, else: fcase]]} | cont],
        env,
        label,
        ctx
      ) do
    {:ok, decider} = actor_from_local_exp(tst_exp, env)

    notify_list =
      case notify_list do
        # don't have decider send to self
        :all -> ctx.actors |> Enum.reject(&(&1 == decider))
        l when is_list(l) -> Enum.map(l, &Macro.expand_once(&1, env))
      end

    monadic do
      tst <- project_local_expr(tst_exp, env, label, ctx)
      tcase_ <- project(normalize_block(tcase), env, label, ctx)
      fcase_ <- project(normalize_block(fcase), env, label, ctx)
      cont_ <- project(normalize_block(cont), env, label, ctx)

      {:__block__, _, continue_header} = function_header(ctx)

      {push_code, func_code} =
        if empty_cont?(cont_, ctx) do
          {quote do
             :empty_continuation
           end, []}
        else
          # used for jumping to cont_
          cont_tok = UUID.uuid4()

          {quote do
             :non_empty_continuation
             state = push_continue_frame(unquote(cont_tok), state)
           end,
           [
             handle_continue:
               quote do
                 def handle_continue(unquote(cont_tok), state) do
                   unquote_splicing(continue_header)
                   unquote(cont_)
                 end
               end
           ]}
        end

      if decider == label do
        quote do
          tst = unquote(tst)

          # send result of tst to notify list
          unquote_splicing(
            for n <- notify_list do
              quote do
                civ_tok = {config.session_token, unquote(meta), unquote(label), unquote(n)}
                send(config[unquote(n)], {:chorex, civ_tok, tst})
              end
            end
          )

          unquote(push_code)

          if tst do
            unquote(tcase_)
          else
            unquote(fcase_)
          end
        end
        |> return_func(func_code)
      else
        if Enum.member?(notify_list, label) do
          k_tok = UUID.uuid4()

          return_func(
            quote do
              # receive from decider
              :receiving_choice
              unquote_splicing(unsplat_state(ctx))
              civ_tok = {config.session_token, unquote(meta), unquote(decider), unquote(label)}

              match_func =
                fn _tst_var -> %{} end

              state =
                push_recv_frame(
                  {civ_tok, match_func, unquote(k_tok)},
                  state
                )

              unquote(function_footer_continue(nil, ctx))
            end,
            func_code ++
              [
                handle_continue:
                  quote do
                    def handle_continue({unquote(k_tok), tst_result}, state) do
                      unquote_splicing(continue_header)

                      unquote(push_code)

                      if tst_result do
                        unquote(tcase_)
                      else
                        unquote(fcase_)
                      end
                    end
                  end
              ]
          )
        else
          # Ensure that tcase_ and fcase_ can merge
          branches = merge(tcase_, fcase_)

          quote do
            unquote(branches)
            unquote(cont_)
          end
          |> return()
        end
      end
    end
  end

  # try do ... rescue ... end
  def project_sequence(
        [{:try, meta, [[do: block1, rescue: block2]]} | cont],
        env,
        label,
        ctx
      ) do
    block1 = normalize_block(block1)
    block2 = normalize_block(block2)
    # FIXME: maybe add the drop-recovery-token bit to the end of each block?

    monadic do
      block1_ <- project(block1, env, label, ctx)
      block2_ <- project(block2, env, label, ctx)
      cont_ <- project(cont, env, label, ctx)

      recover_token = UUID.uuid4() # signal to jump to block2_ (error recovery)
      barrier_id = meta # barrier id must be same for all actors
      {:__block__, _, continue_header} = function_header(ctx)

      {push_code, func_code} =
        if empty_cont?(cont_, ctx) do
          {quote do
             :empty_continuation
           end, []}
        else
          # used for jumping to cont_
          cont_tok = UUID.uuid4()

          {quote do
             :non_empty_continuation
             state = push_continue_frame(unquote(cont_tok), state)
           end,
           [
             handle_continue:
               quote do
                 def handle_continue(unquote(cont_tok), state) do
                   unquote_splicing(continue_header)
                   unquote(cont_)
                 end
               end
           ]}
        end

      return_func(
        quote do
          # push the continuation
          unquote(push_code)

          # push recovery token onto stack
          state = push_recover_frame(unquote(recover_token), state)

          # push barrier token onto stack
          barrier_token = {:barrier, state.session_token, unquote(barrier_id)}
          state = push_barrier_frame(unquote(barrier_id), state)

          # notify monitor to begin
          RuntimeMonitor.begin_checkpoint(state.config.monitor, barrier_token)

          # send state to monitor
          RuntimeMonitor.checkpoint_state(state.config.monitor, unquote(label), unquote(recover_token), state)

          # Run code in block body
          unquote(block1_)

          # notify Monitor block is complete
          RuntimeMonitor.end_checkpoint(state.config.monitor, unquote(label), barrier_token)

          # Finish here and await for the barrier to pass
          # Barrier handling code is in Runtime module
          {:noreply, state}
        end,
        func_code ++            # continuation lives in func_code
          [
            handle_continue:
              quote do
                def handle_continue({:recover, unquote(recover_token)}, state) do
                  unquote_splicing(continue_header)
                  unquote(block2_)
                end
              end
          ]
      )
    end
  end

  # Alice.e ~> Bob.x
  def project_sequence([{:~>, meta, [party1, party2]} | cont], env, label, ctx) do
    {:ok, actor1} = actor_from_local_exp(party1, env)
    {:ok, actor2} = actor_from_local_exp(party2, env)

    monadic do
      sender_exp <- project_local_expr(party1, env, actor1, ctx)
      recver_exp <- project_local_expr(party2, env, actor2, ctx)

      case {actor1, actor2} do
        {^label, ^label} ->
          raise ProjectionError, message: "Can't project sending self a message"

        # Sender side
        {^label, _} ->
          monadic do
            cont_ <-
              project_sequence(cont, env, label, ctx)

            cont__ <-
              cont_or_return(cont_, nil, ctx)

            return(
              quote do
                :sender_sending

                civ_tok =
                  {config.session_token, unquote(meta), unquote(actor1), unquote(actor2)}

                unquote(tron(:msg, sender_exp, :sender, actor1, actor2))

                send(
                  config[unquote(actor2)],
                  {:chorex, civ_tok, unquote(sender_exp)}
                )

                unquote(cont__)
              end
            )
          end

        # Receiver side
        {_, ^label} ->
          k_tok = UUID.uuid4()
          {_free, pattern_vars} = extract_pattern_vars(recver_exp)
          post_recv_ctx = %{ctx | vars: Enum.map(pattern_vars, &elem(&1, 0)) ++ ctx.vars}
          {:__block__, _, continue_header} = function_header(ctx)

          recver_vars_map =
            {:%{}, metadata(party2), Enum.map(pattern_vars, &{elem(&1, 0), &1})}

          monadic do
            cont_ <- project_sequence(cont, env, label, post_recv_ctx)
            cont__ <- cont_or_return(cont_, nil, post_recv_ctx)

            return_func(
              quote do
                :receiver_receiving
                unquote_splicing(unsplat_state(ctx))

                civ_tok =
                  {config.session_token, unquote(meta), unquote(actor1), unquote(actor2)}

                # match_func contract: must return a map of variables
                # used by Chorex.Runtime.handle_continue(:try_recv, state)
                match_func =
                  fn unquote(recver_exp) -> unquote(recver_vars_map) end

                state =
                  push_recv_frame(
                    {civ_tok, match_func, unquote(k_tok)},
                    state
                  )

                unquote(function_footer_continue(nil, ctx))
              end,
              {:handle_continue,
               quote do
                 def handle_continue({unquote(k_tok), unquote(recver_exp)}, state) do
                   unquote_splicing(continue_header)
                   unquote(cont__)
                 end
               end}
            )
          end

        # Not a party to this communication
        {_, _} ->
          project_sequence(cont, env, label, ctx)
      end
    end
  end

  # Local expressions of the form Actor.thing or Actor.(thing)
  def project_sequence(
        [{{:., _, [{:__aliases__, _, _} | _]}, _, _} = expr | cont],
        env,
        label,
        ctx
      ) do
    monadic do
      zero <- mzero()
      expr_ <- project_local_expr(expr, env, label, ctx)
      cont_ <- project_sequence(cont, env, label, ctx)

      if match?(^zero, expr_) do
        # return var is `nil` because the projected expression is an
        # empty block; this means that the local expression is not for
        # this label
        cont_or_return(cont_, nil, ctx)
      else
        fresh_return = Macro.var(:ret, __MODULE__)

        monadic do
          cont__ <- cont_or_return(cont_, fresh_return, ctx)

          quote do
            # generate the fresh return variable because this is an
            # expression for this label
            unquote(fresh_return) = unquote(expr_)
            :need_to_return
            unquote(cont__)
          end
          |> return()
        end
      end
    end
  end

  # let notation, but we're using `with' syntax from Elixir
  # with Alice.var <- expr do ... end
  def project_sequence(
        [{:with, meta1, [{:<-, _, [var, expr]}, [do: body]]} | cont],
        env,
        label,
        ctx
      ) do
    {:ok, actor} = actor_from_local_exp(var, env)

    # Normalize body
    body = normalize_block(body, meta1)

    monadic do
      zero <- mzero()
      match_expr_ <- project_local_expr(var, env, label, ctx)
      expr_ <- project_sequence([expr], env, label, ctx)

      body_ <-
        project(body, env, label, %{
          ctx
          | vars:
              if(match?(^zero, match_expr_),
                do: ctx.vars,
                else: FreeVarAnalysis.extract_new_pattern_var_names(match_expr_) ++ ctx.vars
              )
        })

      cont_ <- project(cont, env, label, ctx)

      # Ensure that we are in tail position
      if not match?(^zero, cont_) do
        line_msg =
          case Keyword.fetch(meta1, :line) do
            {:ok, ln} -> " at line #{ln}"
            :error -> ""
          end

        raise ProjectionError,
          message: "with block#{line_msg} must be in tail position with respect to actor #{label}"
      else
        ktok = UUID.uuid4()

        if actor == label do
          return_func(
            quote do
              # We do some duplicate work unsplatting here: we need
              # the variables packed into `state` variable before we
              # push it onto the stack. This way, when the expr_
              # projection "returns", it will restore the variables
              # that were in scope when the `with` block started.
              unquote_splicing(unsplat_state(ctx))
              state = push_func_frame(unquote(ktok), state)
              unquote(expr_)
            end,
            {:handle_continue, make_var_continue_function(ktok, match_expr_, body_, ctx)}
          )
        else
          return_func(
            quote do
              # push something into the stack in state
              unquote_splicing(unsplat_state(ctx))
              state = push_func_frame(unquote(ktok), state)
              unquote(expr_)
            end,
            {:handle_continue, make_continue_function(ktok, body_, ctx)}
          )
        end
      end
    end
  end

  def project_sequence(
        [{:with, meta, [{:<-, _, _} = hd | [{:<-, _, _} | _] = rst]} | cont],
        env,
        label,
        ctx
      ) do
    project_sequence([{:with, meta, [hd, [do: {:with, meta, rst}]]} | cont], env, label, ctx)
  end

  # Application projection
  def project_sequence([{fn_name, _meta, args} | cont], env, label, ctx)
      when is_atom(fn_name) do
    ktok = UUID.uuid4()

    monadic do
      zero <- mzero()
      args_ <- mapM(args, &project_local_expr(&1, env, label, ctx))
      cont_ <- project_sequence(cont, env, label, ctx)

      if match?(^zero, cont_) do
        # Tail call: don't grow stack
        return(
          quote do
            unquote_splicing(unsplat_state(ctx))
            :tail_call
            unquote(fn_name)(unquote_splicing(args_), %{state | vars: %{}})
          end
        )
      else
        return_func(
          quote do
            unquote_splicing(unsplat_state(ctx))
            :non_tail_call

            # Thread the state through; clean out the variables though
            # Push local variables onto state stack
            state = push_func_frame(unquote(ktok), state)
            unquote(fn_name)(unquote_splicing(args_), %{state | vars: {}})
          end,
          {:handle_continue, make_continue_function(ktok, cont_, ctx)}
        )
      end
    end
  end

  # Applying functions stored in variables: some_func.(args)
  def project_sequence(
        [{{:., _m1, [{fn_var_name, _m2, _ctx} = fn_var]}, _m3, args} | cont],
        env,
        label,
        ctx
      )
      when is_atom(fn_var_name) do
    ktok = UUID.uuid4()

    monadic do
      args_ <- mapM(args, &project_local_expr(&1, env, label, ctx))
      cont_ <- project_sequence(cont, env, label, ctx)

      return_func(
        quote do
          unquote_splicing(unsplat_state(ctx))

          state = push_func_frame(unquote(ktok), state)
          unquote(fn_var).(unquote_splicing(args_), %{state | vars: %{}})
        end,
        {:handle_continue, make_continue_function(ktok, cont_, ctx)}
      )
    end
  end

  def project_sequence([expr | cont], env, label, ctx) do
    monadic do
      expr_ <- project(expr, env, label, ctx)
      cont_ <- project_sequence(cont, env, label, ctx)

      return(
        quote do
          unquote(expr_)
          unquote(cont_)
        end
        |> flatten_block()
      )
    end
  end

  # Handle cases where there is only one thing in a sequence
  def project_sequence(expr, env, label, ctx),
    do: project(expr, env, label, ctx)

  #
  # Local expression handling
  #

  @doc """
  Get the actor name from an expression

      iex> Chorex.actor_from_local_exp((quote do: Foo.bar(42)), __ENV__)
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
  Project an expression like `Actor.var` to either `var` or `_`.

  Project to `var` when `Actor` matches the label we're projecting to,
  or `_` so that whatever data flows to that point can't be captured.
  """
  def project_identifier({{:., _m0, [actor]}, _m1, [var]}, env, label) do
    {:ok, actor} = actor_from_local_exp(actor, env)

    if actor == label do
      return(var)
    else
      return(Macro.var(:_, nil))
    end
  end

  def project_identifier({var, _m, _ctx} = stx, _env, _label)
      when is_atom(var) do
    return(stx)
  end

  @doc """
  Project local expressions of the form `ActorName.(something)`.

  Like `project/4`, but focus on handling `ActorName.(local_var)`,
  `ActorName.local_func()` or `ActorName.(local_exp)`. Handles walking
  the local expression to gather list of functions needed for the
  behaviour to implement.
  """
  # Foo.var or Foo.func(...)
  def project_local_expr(
        {{:., _m0, [actor, var_or_func]}, m1, maybe_args},
        env,
        label,
        ctx
      )
      when is_atom(var_or_func) do
    {:ok, actor} = actor_from_local_exp(actor, env)

    if actor == label do
      case Keyword.fetch(m1, :no_parens) do
        # Foo.var
        {:ok, true} ->
          return(Macro.var(var_or_func, nil))

        # Foo.func(...)
        _ ->
          monadic do
            args <- mapM(maybe_args, &walk_local_expr(&1, env, label, ctx))

            return(
              quote do
                impl.unquote(var_or_func)(unquote_splicing(args))
              end,
              [{actor, {var_or_func, length(args)}}]
            )
          end
      end
    else
      mzero()
    end
  end

  # Foo.(exp)
  def project_local_expr(
        {{:., _m0, [actor]}, _m1, [exp]},
        env,
        label,
        ctx
      ) do
    with {:ok, actor} <- actor_from_local_exp(actor, env) do
      if actor == label do
        walk_local_expr(exp, env, label, ctx)
      else
        mzero()
      end
    else
      :error ->
        # No actor; treat as variable
        {var_name, _var_meta, _var_ctx} = actor

        monadic do
          exp_ <- project(exp, env, label, ctx)

          return(
            quote do
              unquote(Macro.var(var_name, nil)).(impl, config, unquote(exp_))
            end
          )
        end
    end
  end

  # @fn_name/3  -  Choreography higher-order function: appears in local expr locations
  def project_local_expr({:/, m1, [{:@, m2, [fn_name]}, arity]}, _env, _label, _ctx)
      when is_number(arity) do
    # arity + 1 to account for the arg `state`
    return({:&, m2, [{:/, m1, [fn_name, arity + 1]}]})
  end

  def project_local_expr({:_, _meta, _ctx1} = stx, _env, _label, _ctx) do
    return(stx)
  end

  def project_local_expr(stx, _, _, _) do
    raise ProjectionError,
      message: "Unable to project local expression: #{Macro.to_string(stx)}"
  end

  def metadata({_, m, _}) when is_list(m), do: m

  @doc """
  Walks a local expression to pull out/convert function calls.

  The `expr` in `Alice.(expr)` can *almost* be dropped directly into
  the projection for the `Alice` node. Here's where that *almost*
  comes in:

   - `Alice.(1 + foo())` needs to be rewritten as `1 + impl.foo()` and
     `foo/0` needs to be added to the list of functions for the Alice
     behaviour.

   - `Alice.some_func(&other_local_func/2)` needs to be rewritten as
     `impl.some_func(&impl.other_local_func/2)` and both `some_func` and
     `other_local_func` need to be added to the list of functions for the
     Alice behaviour.

   - `Alice.(1 + Enum.sum(...))` should *not* be rewritten as `impl.…`.

  There is some subtlety around tuples and function calls. Consider
  how these expressions and their quoted representations compare:

   - `{:ok, foo}` → `{:ok, {:foo, [], …}}`

   - `{:ok, foo, bar}` → `{:{}, [], [:ok, {:foo, [], …}, {:bar, [], …}]}`

   - `ok(bar)` → `{:ok, [], [{:bar, [], …}]}`

  It seems that 2-tuples have some special representation, which is frustrating.
  """
  def walk_local_expr(code, env, label, ctx) do
    {code, acc} = Macro.postwalk(code, [], &do_local_project_wrapper(&1, &2, env, label, ctx))
    return(code, acc)
  end

  def do_local_project_wrapper(code, acc, env, label, ctx) do
    # We should never synthesize new functions, so last tuple value is []
    {code_, acc_, []} = do_local_project(code, acc, env, label, ctx)
    {code_, acc_}
  end

  # Magic variables (get projected to something special)
  defp do_local_project({:@, _, [{:chorex_config, _, _}]}, acc, _env, _label, _ctx) do
    # We're using __MODULE__ here because the =config= variable is
    # synthesized *by* Chorex's projection functions.
    return(Macro.var(:config, __MODULE__), acc)
  end

  # References to functions (if not prefixed with a module, it needs
  # to get impl. prefix and added to behaviour list)
  defp do_local_project({:&, m1, [{:/, m2, [fn_name, arity]}]} = stx, acc, _env, label, _ctx)
       when is_integer(arity) do
    case fn_name do
      {fn_name, _, _} when is_atom(fn_name) ->
        stx =
          {:&, m1,
           [
             {:/, m2,
              [
                {{:., [], [Macro.var(:impl, __MODULE__), fn_name]}, [no_parens: true], []},
                arity
              ]}
           ]}

        return(stx, [{label, {fn_name, arity}} | acc])

      {{:., _, _}, _, _} ->
        return(stx, acc)
    end
  end

  defp do_local_project({varname, _meta, nil} = var, acc, _env, _label, _ctx)
       when is_atom(varname) do
    return(var, acc)
  end

  defp do_local_project({funcname, _meta, args} = funcall, acc, _env, label, _ctx)
       when is_atom(funcname) and is_list(args) do
    num_args = length(args)
    variadics = [:{}, :%{}]
    builtins = Kernel.__info__(:functions) ++ Kernel.__info__(:macros)

    cond do
      # __aliases__ is a special form and stays as-is.
      :__aliases__ == funcname ->
        return(funcall, acc)

      # Foo.bar() should just get returned; that alias is a module
      # name like IO or Enum.
      match?({:., [{:__aliases__, _, _} | _]}, {funcname, args}) ->
        return(funcall, acc)

      # Calls to functions in Erlang modules also need to get returned
      # verbatim: something like :crypto.generate_key() for example.
      match?(
        {:., [erlang_mod, func_name | _]} when is_atom(erlang_mod) and is_atom(func_name),
        {funcname, args}
      ) ->
        return(funcall, acc)

      Enum.member?(variadics, funcname) ->
        return(funcall, acc)

      Enum.member?(builtins, {funcname, num_args}) ->
        return(funcall, acc)

      true ->
        return(
          quote do
            unquote(Macro.var(:impl, __MODULE__)).unquote(funcname)(unquote_splicing(args))
          end,
          [{label, {funcname, length(args)}} | acc]
        )
    end
  end

  defp do_local_project(x, acc, _env, _label, _ctx) do
    return(x, acc)
  end

  defp normalize_block(stx, meta \\ [])

  defp normalize_block({:__block__, meta, body}, _meta) do
    {:__block__, meta, flatten_block(body)}
  end

  defp normalize_block(stx, meta) do
    body = if(is_list(stx), do: stx, else: [stx]) |> flatten_block()
    {:__block__, meta, body}
  end

  #
  # State and call/return helpers
  #

  def function_header(ctx) do
    quote do
      ret = nil
      unquote_splicing(splat_state(ctx))
    end
    |> flatten_block()
  end

  def function_footer(ctx) do
    quote do
      unquote_splicing(unsplat_state(ctx))
      {:noreply, state}
    end
  end

  def function_footer_continue(var, ctx) do
    quote do
      unquote_splicing(unsplat_state(ctx))
      continue_on_stack(unquote(var), state)
    end
    |> flatten_block()
  end

  def push_stack(new_frame) do
    quote do
      state = %{state | stack: [unquote(new_frame) | state.stack]}
    end
  end

  def splat_state(%{vars: vars}) do
    assigns =
      for v <- vars do
        # FIX HERE: I need to inject these, not in the `nil` context,
        # but in the context of the module I'm expanding into. Yikes
        vv = Macro.var(v, nil)

        quote do
          unquote(vv) = state.vars[unquote(v)]
        end
      end

    extras = [
      quote do
        config = state.config
      end,
      quote do
        impl = state.impl
      end
    ]

    assigns ++ extras
  end

  def unsplat_state(%{vars: vars}) do
    assigns =
      for v <- vars do
        vv = Macro.var(v, nil)
        # Here's an example where you *need* macros that expand to
        # other macros: put_in is a macro!
        quote do
          state = put_in(state.vars[unquote(v)], unquote(vv))
        end
      end

    extras = [
      quote do
        state = %{state | config: config}
      end,
      quote do
        state = %{state | impl: impl}
      end
    ]

    assigns ++ extras
  end

  def cont_or_return({:__block__, [], []}, ret_var, ctx) do
    quote do
      :here_return
      unquote_splicing(unsplat_state(ctx))
      unquote(make_continue(ret_var))
    end
    |> return()
  end

  def cont_or_return(cont_exp, _, _) do
    return(cont_exp)
  end

  @doc """
  True if the continuation for the given code is empty. This can be
  from an empty block, or because the projection of block does
  nothing meaningful.
  """
  def empty_cont?({:__block__, _, []}, _), do: true

  def empty_cont?(code, ctx) do
    {mt_code, _, _} = cont_or_return({:__block__, [], []}, nil, ctx)
    mt_code == code
  end

  def make_continue(_ret_var) do
    quote do
      continue_on_stack(ret, state)
    end
  end

  def make_continue_function(ret_tok, cont, ctx) do
    quote do
      def handle_continue({unquote(ret_tok), return_value}, state) do
        unquote_splicing(splat_state(ctx))
        ret = return_value
        unquote(tron(:dbg, "idk", "handle_continue", ret_tok))
        unquote(cont_or_return(cont, nil, ctx) |> fromEmpyWriter())
      end
    end
  end

  def make_var_continue_function(ret_tok, var_expr, cont, ctx) do
    quote do
      def handle_continue({unquote(ret_tok), return_value}, state) do
        unquote_splicing(splat_state(ctx))
        ret = return_value
        unquote(var_expr) = return_value
        unquote(tron(:dbg, "idk", "handle_continue (var)", ret_tok))
        unquote(cont_or_return(cont, nil, ctx) |> fromEmpyWriter())
      end
    end
  end

  @doc """
  Perform the control merge function.

  Flatten block expressions at each step: sometimes auxiliary blocks
  get created around bits of the projection; trim these out at this
  step so equivalent expressions look equivalent.
  """
  def merge(x, x), do: x
  def merge(x, y), do: merge_step(flatten_block(x), flatten_block(y))

  def merge_step(x, x), do: x

  def merge_step(
        {:if, m1, [test, [do: tcase1, else: fcase1]]},
        {:if, _m2, [test, [do: tcase2, else: fcase2]]}
      ) do
    {:if, m1, [test, [do: merge(tcase1, tcase2), else: merge(fcase1, fcase2)]]}
  end

  def merge_step(
        {:__block__, m1, [hd | rst1]},
        {:__block__, m2, [hd | rst2]}
      ) do
    quote do
      unquote(hd)
      unquote(merge_step({:__block__, m1, rst1}, {:__block__, m2, rst2}) |> flatten_block())
    end
  end

  # def merge_step(
  #       {:__block__, _,
  #        [
  #          {:=, _,
  #           [{:tok, _, _}, {{:., _, [Access, :get]}, _, [{:config, _, _}, :session_token]}]} =
  #            tok_get,
  #          {:receive, _, _} = lhs_rcv
  #        ]},
  #       {:__block__, _, [tok_get, {:receive, _, _} = rhs_rcv]}
  #     ) do
  #   quote do
  #     unquote(tok_get)
  #     unquote(merge_step(lhs_rcv, rhs_rcv))
  #   end
  # end

  def merge_step(
        {:receive, _,
         [[do: [{:->, _, [[{:{}, _, [:choice, tok, civ, agent, dest, L]}], l_branch]}]]]},
        {:receive, _,
         [[do: [{:->, _, [[{:{}, _, [:choice, tok, civ, agent, dest, R]}], r_branch]}]]]}
      ) do
    quote do
      receive do
        {:choice, unquote(tok), unquote(civ), unquote(agent), unquote(dest), L} ->
          unquote(l_branch)

        {:choice, unquote(tok), unquote(civ), unquote(agent), unquote(dest), R} ->
          unquote(r_branch)
      end
    end
  end

  # flip order of branches
  def merge_step(
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, _, _, _, R]}], _]}]]]} = rhs,
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, _, _, _, L]}], _]}]]]} = lhs
      ) do
    merge_step(lhs, rhs)
  end

  # merge same branch
  def merge_step(
        {:receive, m1,
         [[do: [{:->, m2, [[{:{}, m3, [:choice, tok, agent, dest, dir]}], branch1]}]]]},
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, tok, agent, dest, dir]}], branch2]}]]]}
      ) do
    {:receive, m1,
     [[do: [{:->, m2, [[{:{}, m3, [:choice, tok, agent, dest, dir]}], merge(branch1, branch2)]}]]]}
  end

  def merge_step(x, y) do
    raise ProjectionError,
      message:
        "Cannot merge terms:\n  term 1:\n#{Macro.to_string(x)}\n  term 2:\n#{Macro.to_string(y)}"
  end

  def tron(:choice, choice, who, sender, receiver) do
    if @tron do
      l =
        case who do
          :sender -> "*#{sender} []~> #{receiver}"
          :receiver -> "#{sender} []~> *#{receiver}"
        end

      quote do
        IO.inspect(unquote(choice), label: unquote(l))
      end
    else
      quote do
      end
    end
  end

  def tron(:msg, s_exp, who, sender, receiver) do
    if @tron do
      l =
        case who do
          :sender -> "*#{sender} ~> #{receiver}"
          :receiver -> "#{sender} ~> *#{receiver}"
        end

      quote do
        IO.inspect(unquote(s_exp), label: unquote(l))
      end
    else
      quote do
      end
    end
  end

  def tron(:dbg, actor, label, data) do
    if @tron do
      quote do
        IO.inspect(unquote(data), label: "[#{unquote(actor)}] #{unquote(label)}")
      end
    else
      quote do
      end
    end
  end

  def proj_dbg(start, stop) do
    start |> Macro.to_string() |> IO.puts()
    IO.puts("\nexpanded to\n")
    stop |> Macro.to_string() |> IO.puts()
  end
end

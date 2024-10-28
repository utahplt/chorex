defmodule Chorex do
  @moduledoc """
  Make your modules dance!

  Chorex allows you to specify a choreography: a birds-eye view of an
  interaction of concurrent parties. Chorex takes that choreography
  creates a *projection* of that interaction for each party in the
  system.

  Take, for example, the classic problem of a book seller and two
  buyers who want to split the price. The interaction looks like this:

  ```
  +------+         +------+ +------+
  |Buyer1|         |Seller| |Buyer2|
  +--+---+         +--+---+ +--+---+
     |                |        |
     |   Book title   |        |
     |--------------->|        |
     |                |        |
     |     Price      |        |
     |<---------------|        |
     |                |        |
     |                |  Price |
     |                |------->|
     |                |        |
     |      Contribution       |
     |<------------------------|
     |                |        |
     |   Buy/No buy   |        |
     |--------------->|        |
     |                |        |
     |(if Buy) address|        |
     |--------------->|        |
     |                |        |
     | Shipping date  |        |
     |<---------------|        |
  +--+---+         +--+---+ +--+---+
  |Buyer1|         |Seller| |Buyer2|
  +------+         +------+ +------+
  ```

  You can encode that interaction with the `defchor` macro and DSL:

  ```elixir
  defmodule ThreePartySeller do
    defchor [Buyer1, Buyer2, Seller] do
      def run() do
        Buyer1.get_book_title() ~> Seller.(b)
        Seller.get_price("book:" <> b) ~> Buyer1.(p)
        Seller.get_price("book:" <> b) ~> Buyer2.(p)
        Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

        if Buyer1.(p - contrib < get_budget()) do
          Buyer1[L] ~> Seller
          Buyer1.get_address() ~> Seller.(addr)
          Seller.get_delivery_date(b, addr) ~> Buyer1.(d_date)
          Buyer1.(d_date)
        else
          Buyer1[R] ~> Seller
          Buyer1.(nil)
        end
      end
    end
  end
  ```

  The `defchor` macro will take care of generating code that handles
  sending messages. Now all you have to do is implement the local
  functions that don't worry about the outside system:

  ```elixir
  defmodule MySeller do
    use ThreePartySeller.Chorex, :seller

    def get_price(book_name), do: ...
    def get_delivery_date(book_name, addr), do: ...
  end

  defmodule MyBuyer1 do
    use ThreePartySeller.Chorex, :buyer1

    def get_book_title(), do: ...
    def get_address(), do: ...
    def get_budget(), do: ...
  end

  defmodule MyBuyer2 do
    use ThreePartySeller.Chorex, :buyer2

    def compute_contrib(price), do: ...
  end
  ```

  What the `defchor` macro actually does is creates a module `Chorex`
  and submodules for each of the actors: `Chorex.Buyer1`,
  `Chorex.Buyer2` and `Chorex.Seller`. There's a handy `__using__`
  macro that will Do the right thing when you say `use Mod.Chorex, :actor_name`
  and will import those modules and say that your module implements
  the associated behaviour. That way, you should get a nice
  compile-time warning if a function is missing.

  ## Starting a choreography

  ### Automatic startup

  Invoke `Chorex.start/3` with:

  1. The module name of the choreography,
  2. A map from actor name to implementation name, and
  3. A list of initial arguments.

  So, you could start the choreography from the previous section with:

  ```elixir
  Chorex.start(ThreePartySeller.Chorex,
               %{ Buyer1 => MyBuyer1,
                  Buyer2 => MyBuyer2,
                  Seller => MySeller },
               [])
  ```

  ### Manual startup

  To start the choreography, you need to invoke the `init` function in
  each of your actors (provided via the `use ...` invocation)
  whereupon each actor will wait to receive a config mapping actor
  name to PID:

  ```elixir
  the_seller = spawn(MySeller, :init, [[]])
  the_buyer1 = spawn(MyBuyer1, :init, [[]])
  the_buyer2 = spawn(MyBuyer2, :init, [[]])

  config = %{Seller1 => the_seller, Buyer1 => the_buyer1, Buyer2 => the_buyer2, :super => self()}

  send(the_seller, {:config, config})
  send(the_buyer1, {:config, config})
  send(the_buyer2, {:config, config})
  ```

  ## Choreography return values

  Each of the parties will try sending the last value they computed
  once they're done running. These messages will get set to whatever
  process kicked the the choreography off.

  ```elixir
  Chorex.start(ThreePartySeller.Chorex,
               %{ Buyer1 => MyBuyer1,
                  Buyer2 => MyBuyer2,
                  Seller => MySeller },
               [])

  receive do
    {:chorex_return, Buyer1, d_date} -> report_delivery(d_date)
  end
  ```

  ## Higher-order choreographies

  Chorex supports higher-order choreographies. For example, you can
  define a generic buyer/seller interaction and abstract away the
  decision process into a higher-order choreography:

  ```elixir
  defmodule TestChor3 do
    defchor [Buyer3, Contributor3, Seller3] do
      def bookseller(decision_func) do
        Buyer3.get_book_title() ~> Seller3.the_book
        with Buyer3.decision <- decision_func.(Seller3.get_price("book:" <> the_book)) do
          if Buyer3.decision do
            Buyer3[L] ~> Seller3
            Buyer3.get_address() ~> Seller3.the_address
            Seller3.get_delivery_date(the_book, the_address) ~> Buyer3.d_date
            Buyer3.d_date
          else
            Buyer3[R] ~> Seller3
            Buyer3.(nil)
          end
        end
      end

      def one_party(Seller3.(the_price)) do
        Seller3.(the_price) ~> Buyer3.(p)
        Buyer3.(p < get_budget())
      end

      def two_party(Seller3.(the_price)) do
        Seller3.(the_price) ~> Buyer3.(p)
        Seller3.(the_price) ~> Contributor3.(p)
        Contributor3.compute_contrib(p) ~> Buyer3.(contrib)
        Buyer3.(p - contrib < get_budget())
      end

      def run(Buyer3.(get_contribution?)) do
        if Buyer3.(get_contribution?) do
          Buyer3[L] ~> Contributor3
          Buyer3[L] ~> Seller3
          bookseller(@two_party/1)
        else
          Buyer3[R] ~> Contributor3
          Buyer3[R] ~> Seller3
          bookseller(@one_party/1)
        end
      end
    end
  end
  ```

  Notice the `@two_part/1` syntax: the `@` is necessary so Chorex
  knows that this is a reference to a function defined inside the
  `defchor` block; it needs to handle these references specially.

  Now, when you start up the choreography, the you can instruct the
  choreography whether or not to run the three-party scenario. The
  first item in the list of arguments will get sent to the node
  running the `Buyer3` behaviour and will be used in the decision
  process inside the `run` function.

  ```elixir
  Chorex.start(TestChor3.Chorex, %{ ... }, [true])  # run 3-party
  Chorex.start(TestChor3.Chorex, %{ ... }, [false]) # run 2-party
  ```

  ## Singletons managing shared state

  Sometimes, you might want to share some state between different
  instances of the same choreography. The classic Elixir solution to
  managing shared state is to use a GenServer: processes interested in
  accessing/modifying the state send messages to the GenServer and await
  replies.

  Chorex provides a mechanism to model this behavior in a choreography.
  Going back to our bookseller example, suppose there is a limited stock
  of books, and the seller must not sell a book twice. The stock of
  books is the shared state, and instances of the seller in the
  choreography need to be able to access this.

  Here is how you define such a choreography:

  ```elixir
  defchor [Buyer, {Seller, :singleton}] do
    def run() do
      Buyer.get_book_title() ~> Seller.(b)
      Seller.get_price(b) ~> Buyer.(p)
      if Buyer.in_budget(p) do
        Buyer[L] ~> Seller
        if Seller.acquire_book(@chorex_config, b) do
          Seller[L] ~> Buyer
          Buyer.(:book_get)
        else
          Seller[R] ~> Buyer
          Buyer.(:darn_missed_it)
        end
      else
        Buyer[R] ~> Seller
        Buyer.(:nevermind)
      end
    end
  end
  ```

  Saying `{Seller, :singleton}` in the `defchor` declaration indicates
  that the `Seller` actor is going to share some state. The `Seller`
  actor can access this shared state in any function, though such
  functions need to have the magic `@chorex_config` variable passed to
  them. (This is just a special symbol recognized by the Chorex
  compiler.)

  In the implementation, the Seller can access the state using the
  `Proxy.update_state` function:

  ```elixir
  defmodule MySellerBackend do
    use BooksellerProxied.Chorex, :seller
    alias Chorex.Proxy

    def get_price(_), do: 42

    def acquire_book(config, book_title) do

      # Attempt to acquire a lock on the book
      Proxy.update_state(config, fn book_stock ->
        with {:ok, count} <- Map.fetch(book_stock, book_title) do
          if count > 0 do
            # Have the book, lock it for this customer
            {true, Map.put(book_stock, book_title, count - 1)}
          else
            {false, book_stock}
          end
        else
          :error ->
            {false, book_stock}
        end
      end)
    end
  end
  ```

  That's it! Now the seller won't accidentally double-sell a book.

  ### The need for a proxy

  Actors that share state do run as a separate process, but a GenServer
  that manages the state also acts as a proxy for all messages to/from
  the actor. This is so that operations touching the shared state happen
  in lockstep with progression through the choreography. We may
  investigate weakening this property in the future.

  ### Setting up a shared-state choreography

  You will need to start a proxy first of all:

  ```elixir
  {:ok, px} = GenServer.start(Chorex.Proxy, %{"Anathem" => 1})
  ```

  The `px` variable now holds the PID of a GenServer running the
  `Chorex.Proxy` module. Now we use this `px` variable in the actor
  map to set up the choreography:

  ```elixir
  Chorex.start(ProxiedBookseller.Chorex,
               %{ Buyer => MyBuyer,
                  Seller => {MySellerBackend, px}},
               [])
  ```

  Note the 2-tuple: the first element is the module to be proxied, and
  the second element should be the PID of an already-running proxy.

  ### Manually setting up the shared-state choreography (deprecated)

  (*Note: we recommend using the `Chorex.start` mechanism now.*)

  You need to be a little careful when setting up the shared state
  choreography. Instead of setting up all the actors manually, you need
  to set up *one* instance of each shared-state actor, then create
  separate *sessions* for each instance of the choreography that you
  want to run.

  Here is an example with two buyers trying to buy the same book:

  ```elixir
  # Start up the buyers
  b1 = spawn(MyBuyer, :init, [[]])
  b2 = spawn(MyBuyer, :init, [[]])

  # Start up the seller proxy with the initial shared
  # state (the stock of books in this case)
  {:ok, px} = GenServer.start(Chorex.Proxy, %{"Anathem" => 1})

  # Start sessions: one for each buyer
  Proxy.begin_session(px, [b1], MySellerBackend, :init, [])
  config1 = %{Buyer => b1, Seller => px, :super => self()}

  Proxy.begin_session(px, [b2], MySellerBackend, :init, [])
  config2 = %{Buyer => b2, Seller => px, :super => self()}

  # Send everyone their configuration
  send(b1, {:config, config1})
  send(px, {:chorex, b1, {:config, config1}})
  send(b2, {:config, config2})
  send(px, {:chorex, b2, {:config, config2}})
  ```

  The `Proxy.begin_sesion` function takes a proxy function, a list of
  PIDs that partake in a given session, and a module, function, arglist
  for the thing to proxy.

  **Sessions**: PIDs belonging to a session will have their messages
  routed to the corresponding proxied process. The GenServer looks up
  which session a PID belongs to, finds the proxied process linked to
  that session, then forwards the message to that process. The exact
  mechanisms of how this works may change in the future to accommodate
  restarts.

  When you send the config information to a proxied process, you send it
  through the proxy first, and you must wrap the message as shown above
  with a process from the session you want to target as the second
  element in the tuple; this just helps the proxy figure out the session
  you want.

  That's it! If you run the above choreography, the process that kicks
  this all off will get *one* message like `{:chorex_return, Buyer, :book_get}`
  and *one* message like `{:chorex_return, Buyer, :darn_missed_it}`,
  indicating that exactly one of the buyers got the coveted book.
  """

  import WriterMonad
  import Utils
  alias Chorex.Proxy

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
    actor_list = chorex_module.get_actors()

    pre_config =
      for actor_desc <- actor_list do
        case actor_desc do
          {a, :singleton} ->
            {backend_module, proxy_pid} = actor_impl_map[a]
            {a, {backend_module, proxy_pid}}

          a when is_atom(a) ->
            case actor_impl_map[a] do
              {:remote, lport, rhost, rport} ->
                {a, {:remote, lport, rhost, rport}}

              m when is_atom(a) ->
                pid = spawn(m, :init, [init_args])
                {a, pid}
            end
        end
      end
      |> Enum.into(%{})

    # Gather up actors that need remote proxies
    remotes =
      pre_config
      |> Enum.flat_map(fn
        {_k, {:remote, _, _, _} = r} -> [r]
        _ -> []
      end)
      |> Enum.into(MapSet)

    remote_proxies =
      for {:remote, lport, rhost, rport} = proxy_desc <- remotes do
        {:ok, proxy_pid} =
          GenServer.start(Chorex.SocketProxy, %{
            listen_port: lport,
            remote_host: rhost,
            remote_port: rport
          })

        {proxy_desc, proxy_pid}
      end
      |> Enum.into(%{})

    session_token = UUID.uuid4()

    config =
      pre_config
      |> Enum.map(fn
        {a, {_backend_module, proxy_pid}} -> {a, proxy_pid}
        {a, {:remote, _, _, _} = r_desc} -> {a, remote_proxies[r_desc]}
        {a, pid} -> {a, pid}
      end)
      |> Enum.into(%{})
      |> Map.put(:super, self())
      |> Map.put(:session_token, session_token)

    for actor_desc <- actor_list do
      case actor_desc do
        {a, :singleton} ->
          {backend_module, px} = pre_config[a]
          Proxy.begin_session(px, session_token, backend_module, :init, [init_args])
          send(px, {:chorex, session_token, :meta, {:config, config}})

        a when is_atom(a) ->
          send(config[a], {:chorex, session_token, :meta, {:config, config}})
      end
    end
  end

  @doc """
  Define a new choreography.

  See the documentation for the `Chorex` module for more details.
  """
  defmacro defchor(actor_list, do: block) do
    # actors is a list of *all* actors;
    {actors, singleton_actors} = process_actor_list(actor_list, __CALLER__)

    ctx = %{empty_ctx() | singletons: singleton_actors}

    projections =
      for {actor, {naked_code, callback_specs, fresh_functions}} <-
            Enum.map(
              actors,
              &{&1, project(block, __CALLER__, &1, ctx)}
            ) do
        # Just the actor; aliases will resolve to the right thing
        modname = actor

        unless match?({:__block__, _, []}, flatten_block(naked_code)) do
          IO.warn("Useless code in choreography: all code must be wrapped inside a block")
        end

        fresh_functions = for {_name, func_code} <- fresh_functions, do: func_code

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

        # Innards of the auto-generated function that will be called
        # when you say "use Foo.Chorex, :actorname"
        inner_func_body =
          quote do
            import unquote(modname)
            unquote(behaviour_decl)

            # This is the function that first gets spawned
            def init(args) do
              unquote(modname).init(__MODULE__, args)
            end
          end

        # Since unquoting deep inside nested templates doesn't work so
        # well, we have to construct the AST ourselves
        func_body = {:quote, [], [[do: inner_func_body]]}

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
            # args whatever was passed as the third arg to Chorex.start
            def init(impl, args) do
              receive do
                {:chorex, session_token, :meta, {:config, config}} ->
                  ret = apply(__MODULE__, :run, [impl, config | args])
                  send(config[:super], {:chorex_return, unquote(actor), ret})
              end
            end

            unquote_splicing(fresh_functions)
          end
        end
      end

    quote do
      defmodule Chorex do
        def get_actors() do
          unquote(actor_list)
        end

        unquote_splicing(projections)

        defmacro __using__(which) do
          apply(__MODULE__, which, [])
        end
      end
    end
  end

  def empty_ctx() do
    %{singletons: []}
  end

  defp process_actor_list([], _), do: {[], []}

  defp process_actor_list([{actor, :singleton} | rst], caller) do
    actor = Macro.expand_once(actor, caller)
    {as, sas} = process_actor_list(rst, caller)
    {[actor | as], [actor | sas]}
  end

  defp process_actor_list([actor | rst], caller) do
    actor = Macro.expand_once(actor, caller)
    {as, sas} = process_actor_list(rst, caller)
    {[actor | as], sas}
  end

  defp process_actor_list(alist, _) do
    raise "Malformed actor list in defchor: #{inspect(alist)}"
  end

  defmodule ProjectionError do
    defexception message: "unable to project"
  end

  @doc """
  Perform endpoint projection in the context of node `label`.

  This returns a pair of a projection for the label, and a list of
  behaviors that an implementer of the label must implement.

  Arguments:

  1. Elixir AST term to project.
  2. Macro environment.
  3. Name of the actor currently under projection. Atom.
  4. Extra information about the expansion. Map. Currently contains
     just a list of actors that will be behind a proxy.

  Returns an instance of the `WriterMonad`, which is just a 3-tuple
  containing:

  1. The projected term. Elixir AST.
  2. A list of callback specifications for this actor. (Functions the
     actor implementer needs to have.)
  3. List of auxiliary functions generated during the projection process.

  """
  @spec project(term :: term(), env :: Macro.Env.t(), label :: atom(), ctx :: map()) ::
          WriterMonad.t()
  def project({:__block__, _meta, [term]}, env, label, ctx),
    do: project(term, env, label, ctx)

  def project({:__block__, _meta, terms}, env, label, ctx),
    do: project_sequence(terms, env, label, ctx)

  # Alice.e ~> Bob.x
  def project(
        {:~>, _meta, [party1, party2]},
        env,
        label,
        ctx
      ) do
    {:ok, actor1} = actor_from_local_exp(party1, env)
    {:ok, actor2} = actor_from_local_exp(party2, env)

    monadic do
      sender_exp <- project_local_expr(party1, env, actor1, ctx)
      recver_exp <- project_local_expr(party2, env, actor2, ctx)

      case {actor1, actor2} do
        {^label, ^label} ->
          raise ProjectionError, message: "Can't project sending self a message"

        {^label, _} ->
          # check: is this a singleton I'm talking to?

          return(
            quote do
              tok = config[:session_token]

              send(
                config[unquote(actor2)],
                {:chorex, tok, unquote(actor1), unquote(actor2), unquote(sender_exp)}
              )
            end
          )

        {_, ^label} ->
          # As far as I can tell, nil is the right context, because when
          # I look at `args' in the previous step, it always has context
          # nil when I'm expanding the real thing.
          return(
            quote do
              tok = config[:session_token]

              unquote(recver_exp) =
                receive do
                  {:chorex, ^tok, unquote(actor1), unquote(actor2), msg} -> msg
                end
            end
          )

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
        label,
        ctx
      ) do
    {:ok, actor} = actor_from_local_exp(tst_exp, env)

    monadic do
      # The test can only run on a single node
      tst <- project_local_expr(tst_exp, env, actor, ctx)
      b1 <- project_sequence(tcase, env, label, ctx)
      b2 <- project_sequence(fcase, env, label, ctx)

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
        label,
        ctx
      ) do
    {:ok, actor} = actor_from_local_exp(var, env)

    monadic do
      var_ <- project(var, env, label, ctx)
      expr_ <- project(expr, env, label, ctx)
      body_ <- project(body, env, label, ctx)

      if actor == label do
        return(
          quote do
            with unquote(var_) <- unquote(expr_) do
              unquote(body_)
            end
          end
        )
      else
        return(
          quote do
            with _ <- unquote(expr_) do
              unquote(body_)
            end
          end
        )
      end
    end
  end

  def project(
        {:with, meta, [{:<-, _, _} = hd | [{:<-, _, _} | _] = rst]},
        env,
        label,
        ctx
      ) do
    project({:with, meta, [hd, [do: {:with, meta, rst}]]}, env, label, ctx)
  end

  # Local expressions of the form Actor.thing or Actor.(thing)
  def project({{:., _, [{:__aliases__, _, _} | _]}, _, _} = expr, env, label, ctx) do
    project_local_expr(expr, env, label, ctx)
  end

  # Applying functions stored in variables: some_func.(args)
  def project({{:., _m1, [{fn_var_name, _m2, _ctx} = fn_var]}, _m3, args}, env, label, ctx)
      when is_atom(fn_var_name) do
    monadic do
      args_ <- mapM(args, &project_local_expr(&1, env, label, ctx))

      return(
        quote do
          unquote(fn_var).(impl, config, unquote_splicing(args_))
        end
      )
    end
  end

  # Function projection
  def project({:def, _meta, [{fn_name, _meta2, params}, [do: body]]}, env, label, ctx) do
    monadic do
      params_ <- mapM(params, &project_identifier(&1, env, label))
      body_ <- project(body, env, label, ctx)
      # no return value from a function definition
      r <- mzero()

      return(
        r,
        [],
        [
          {fn_name,
           quote do
             def unquote(fn_name)(impl, config, unquote_splicing(params_)) do
               unquote(body_)
             end
           end}
        ]
      )
    end
  end

  # Application projection
  def project({fn_name, _meta, args}, env, label, ctx)
      when is_atom(fn_name) do
    monadic do
      args_ <- mapM(args, &project_local_expr(&1, env, label, ctx))

      return(
        quote do
          unquote(fn_name)(impl, config, unquote_splicing(args_))
        end
      )
    end
  end

  def project(code, _env, _label, _ctx) do
    raise ProjectionError,
      message: "No projection for form: #{Macro.to_string(code)}\n   Stx: #{inspect(code)}"
  end

  #
  # Projecting sequence of statements
  #

  @doc """
  Project a sequence of expressions, such as those found in a block.
  """
  @spec project_sequence(term(), Macro.Env.t(), atom(), map()) :: WriterMonad.t()
  def project_sequence(
        {:__block__, _meta, [expr]},
        env,
        label,
        ctx
      ) do
    project(expr, env, label, ctx)
  end

  def project_sequence(
        {:__block__, _meta, [_ | _] = exprs},
        env,
        label,
        ctx
      ) do
    project_sequence(exprs, env, label, ctx)
  end

  # Choice information: Alice[L] ~> Bob
  def project_sequence(
        [
          {:~>, _meta,
           [
             {{:., [{:from_brackets, true} | _], [Access, :get]}, [{:from_brackets, true} | _],
              [
                sender_alias,
                choice_alias
              ]},
             dest_alias
           ]}
          | cont
        ],
        env,
        label,
        ctx
      ) do
    sender = Macro.expand_once(sender_alias, env)
    choice = Macro.expand_once(choice_alias, env)
    dest = Macro.expand_once(dest_alias, env)

    monadic do
      cont_ <- project_sequence(cont, env, label, ctx)

      case {sender, dest} do
        {^label, _} ->
          return(
            quote do
              tok = config[:session_token]

              send(
                config[unquote(dest)],
                {:choice, tok, unquote(sender), unquote(dest), unquote(choice)}
              )

              unquote(cont_)
            end
          )

        {_, ^label} ->
          return(
            quote do
              tok = config[:session_token]

              receive do
                {:choice, ^tok, unquote(sender), unquote(dest), unquote(choice)} ->
                  unquote(cont_)
              end
            end
          )

        _ ->
          return(cont_)
      end
    end
  end

  def project_sequence([expr], env, label, ctx) do
    project(expr, env, label, ctx)
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

  # Foo.(expr)
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
    # arity + 2 to account for the args `impl` and `config`
    return({:&, m2, [{:/, m1, [fn_name, arity + 2]}]})
  end

  def project_local_expr({:_, _meta, _ctx1} = stx, _env, _label, _ctx) do
    return(stx)
  end

  def project_local_expr(stx, _, _, _) do
    raise ProjectionError,
      message: "Unable to project local expression: #{Macro.to_string(stx)}"
  end

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
                {{:., [], [Macro.var(:impl, nil), fn_name]}, [no_parens: true], []},
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
            impl.unquote(funcname)(unquote_splicing(args))
          end,
          [{label, {funcname, length(args)}} | acc]
        )
    end
  end

  defp do_local_project(x, acc, _env, _label, _ctx) do
    return(x, acc)
  end

  @doc """
  Flatten nested block expressions as much as possible.

  Turn something like

  ```elixir
  do
    do
      …
    end
  end
  ```

  into simply

  ```elixir
  do
    …
    end
  ```

  This is important for the `merge/2` function to be able to tell when
  two expressions are equivalent.
  """
  def flatten_block({:__block__, _meta, [expr]}), do: expr

  def flatten_block({:__block__, meta, exprs}) do
    exprs
    |> Enum.map(&flatten_block/1)
    # drop empty blocks
    |> Enum.filter(fn
      {:__block__, _, []} -> false
      _ -> true
    end)
    |> then(&{:__block__, meta, &1})
  end

  def flatten_block({other, meta, exprs}) when is_list(exprs),
    do: {other, meta, Enum.map(exprs, &flatten_block/1)}

  def flatten_block(other), do: other

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
    {:__block__, _, [{:=, _, [{:tok, _, _}, {{:., _, [Access, :get]}, _, [{:config, _, _}, :session_token]}]} = tok_get, {:receive, _, _} = lhs_rcv]},
    {:__block__, _, [tok_get, {:receive, _, _} = rhs_rcv]}) do
    quote do
      unquote(tok_get)
      unquote(merge_step(lhs_rcv, rhs_rcv))
    end
  end

  def merge_step(
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, tok, agent, dest, L]}], l_branch]}]]]},
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, tok, agent, dest, R]}], r_branch]}]]]}
      ) do
    quote do
      receive do
        {:choice, unquote(tok), unquote(agent), unquote(dest), L} -> unquote(l_branch)
        {:choice, unquote(tok), unquote(agent), unquote(dest), R} -> unquote(r_branch)
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
        {:receive, m1, [[do: [{:->, m2, [[{:{}, m3, [:choice, tok, agent, dest, dir]}], branch1]}]]]},
        {:receive, _, [[do: [{:->, _, [[{:{}, _, [:choice, tok, agent, dest, dir]}], branch2]}]]]}
      ) do
    {:receive, m1,
     [[do: [{:->, m2, [[{:{}, m3, [:choice, tok, agent, dest, dir]}], merge(branch1, branch2)]}]]]}
  end

  def merge_step(x, y) do
    raise ProjectionError,
      message: "Cannot merge terms:\n  term 1: #{inspect(x)}\n  term 2: #{inspect(y)}"
  end
end

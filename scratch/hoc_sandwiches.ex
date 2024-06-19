defmodule HocSandwiches do
  @moduledoc """
  Higher-Order Sandwiches, LLC
  """

  defmodule StoreProxy do
    use GenServer

    @type session_key :: term()
    @type state :: %{pid_session: %{pid() => session_key()},
                     session_data: %{session_key() => any()},
                     session_handler: %{session_key() => pid()}}

    def handle_cast({:begin_session, pids, initial_state}, state) do
      session_key = :erlang.monotonic_time()
      {child, child_ref} = spawn_monitor(StoreBackend, :init, [MyStoreBackendImpl])
      pids
      |> Enum.reduce(%{}, fn p, acc -> Map.put(acc, p, session_key) end)
      |> then(&Map.update!(state, :pid_session, fn old -> Map.merge(old, &1) end))
      |> put_in([:session_data, session_key], initial_state)
      |> put_in([:session_handler, session_key], child)
      |> then(&{:no_reply, &1})
    end

    def handle_info({:chorex, sender, msg}, state) when is_pid(sender) do
      with {:ok, session_key} <- Map.fetch(state[:pid_session], sender),
           {:ok, state} <- Map.fetch(state[:session_data], session_key),
           {:ok, handler} <- Map.fetch(state[:session_handler], session_key) do
        # FIXME: how do I want to thread the shared resource through?
        send(handler, msg)
      end
    end
  end

  defmodule StoreBackend do
    @callback make_sandwich(any(), any()) :: any()
    def init(impl) do
      receive do
        {:config, config} ->
          ret = run_choreography(impl, config)
          send(config[:super], {:chorex_return, StoreBackend, ret})
      end
    end

    def big_chor(impl, config, sandwich_internals) do
      bread =
        receive do
        msg -> msg
      end

      with ingredient_stack <- sandwich_internals.(impl, config, nil) do
        send(config[Alice], impl.make_sandwich(bread, ingredient_stack))
      end
    end

    def pbj(impl, config, _input_x) do
      receive do
        {:choice, Alice, L} ->
          wash_hands =
            receive do
            msg -> msg
          end

        {:choice, Alice, R} ->
          nil
      end
    end

    def hamncheese(impl, config, _input_x) do
    end

    def run_choreography(impl, config) do
      if function_exported?(impl, :run_choreography, 2) do
        impl.run_choreography(impl, config)
      else
        big_chor(impl, config, &pbj/3)
      end
    end
  end

  defmacro __using__(which) do
    apply(__MODULE__, which, [])
  end

  defmodule MyStoreBackendImpl do
    import StoreBackend
    @behaviour StoreBackend

    def make_sandwich(bread, ingredients), do: [bread] ++ ingredients ++ [bread]
  end


  defmodule Chorex do
    def alice do
      quote do
        import Alice
        @behaviour Alice
        def init() do
          Alice.init(__MODULE__)
        end
      end
    end

    defmodule Alice do
      @callback allergic_to(any(), any()) :: any()
      @callback plz_wash() :: any()
      @callback allergic_to(any(), any()) :: any()
      @callback get_allergens() :: any()
      @callback get_bread() :: any()
      def init(impl) do
        receive do
          {:config, config} ->
            ret = run_choreography(impl, config)
            send(config[:super], {:chorex_return, Alice, ret})
        end
      end

      def big_chor(impl, config, sandwich_internals) do
        send(config[StoreProxy], impl.get_bread())

        with _ <- sandwich_internals.(impl, config, impl.get_allergens()) do
          sammich =
            receive do
            msg -> msg
          end

          sammich
        end
      end

      def pbj(impl, config, allergens) do
        if impl.allergic_to(allergens, "peanut_butter") do
          send(config[StoreProxy], {:choice, Alice, L})

          (
            send(config[StoreProxy], impl.plz_wash())
            ["almond_butter", "raspberry_jam"]
          )
        else
          send(config[StoreProxy], {:choice, Alice, R})
          ["peanut_butter", "raspberry_jam"]
        end
      end

      def hamncheese(impl, config, allergens) do
        if impl.allergic_to(allergens, "dairy") do
          ["ham", "tomato"]
        else
          ["ham", "swiss_cheese", "tomato"]
        end
      end

      def run_choreography(impl, config) do
        if function_exported?(impl, :run_choreography, 2) do
          impl.run_choreography(impl, config)
        else
          big_chor(impl, config, &pbj/3)
        end
      end
    end
  end
end

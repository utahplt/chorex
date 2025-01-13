defmodule Chorex.Runtime do
  defguard correct_session(m, s) when elem(m, 0) == s.session_tok

  @typedoc """
    A CIV token is a string (UUID) indicating the session, the line
    information identifying the message, the sender name, and the
    receiver name.
  """
  @type civ_tok :: {String.t(), any(), atom(), atom()}

  @typedoc "A chorex message looks like the atom `:chorex`, a `civ_tok()`, and a payload"
  @type chorex_message :: {:chorex, civ_tok(), payload :: any()}

  @type var_map :: %{} | %{atom() => any()}

  @typedoc "An entry in the inbox looks like a CIV token × message payload"
  @type inbox_msg :: {civ_tok(), msg :: any()}

  @type stack_frame ::
          {:recv, civ_tok :: civ_tok(), msg_pat :: any(), cont_tok :: String.t(), vars :: var_map()}
          | {:return, cont_tok :: String.t(), vars :: var_map()}

  @type runtime_state :: %{
          config: nil | %{atom() => pid()},
          impl: atom(),
          session_tok: String.t(),
          vars: var_map(),
          inbox: {[inbox_msg()], [inbox_msg()]},
          stack: [stack_frame()]
        }

  #
  # ----- Helper functions -----
  #

  @spec push_inbox(inbox_msg(), runtime_state()) :: runtime_state()
  def push_inbox(msg, state), do: %{state | inbox: :queue.cons(msg, state.inbox)}

  @spec drop_inbox(inbox_msg(), runtime_state()) :: runtime_state()
  def drop_inbox(msg, state), do: %{state | inbox: :queue.delete(msg, state.inbox)}

  @spec push_recv_frame({civ_tok(), any(), String.t(), var_map()}, runtime_state()) :: runtime_state()
  def push_recv_frame({civ_tok, msg_pat, cont_tok, vars}, state) do
    %{state | stack: [{:recv, civ_tok, msg_pat, cont_tok, vars} | state.stack]}
  end

  @spec push_func_frame({String.t(), var_map()}, runtime_state()) :: runtime_state()
  def push_func_frame({cont_tok, vars}, state) do
    %{state | stack: [{:return, cont_tok, vars} | state.stack]}
  end

  # Looks at the stack and emits the proper return tuple
  @spec continue_on_stack(any(), runtime_state()) :: {:noreply, runtime_state(), {:continue, any()}}
  def continue_on_stack(ret_val, state) do
    case state.stack do
      [{:recv, _, _, _, _} | _] ->
        {:noreply, state, {:continue, :try_recv}}

      [{:return, _, _}] ->
        {:noreply, state, {:continue, {:return, ret_val}}}
    end
  end

  #
  # ----- GenServer functions -----
  #

  def init({actor_name, impl_name, return_to, session_tok}) do
    state = %{
      # network configuration
      config: nil,
      # name of this actor
      actor: actor_name,
      # name of implementing module
      impl: impl_name,
      # session token
      session_tok: session_tok,
      # local variables
      vars: %{},
      # waiting messages
      inbox: :queue.new(),
      # call stack
      stack: [{:return, "chorex_return", %{parent: return_to}}]
    }

    {:ok, state}
  end

  def handle_info({:config, config}, state) do
    dbg(config)
    (state.impl).run(%{state | config: config})
    # {:noreply, %{state | config: config}}
  end

  def handle_info({:chorex, civ_tok, msg}, state)
      when correct_session(civ_tok, state) do
    {:noreply, push_inbox({civ_tok, msg}, state), {:continue, :try_recv}}
  end

  def handle_continue(:try_recv, state) do
    # Run through state.inbox looking for something matching `(car state.stack)`
    [{:recv, civ_tok, msg_pat, cont_tok, vars} | rst_stack] = state.stack

    # FIXME: what do I do with pinned variables? Do I need to use `vars` somehow?

    dbg([needle: msg_pat])
    dbg(state.inbox)
    # Find the first thing in the queue matching `msg_pat` and drop it
    matcher =
      state.inbox
      |> :queue.to_list()
      |> Enum.find(&match?({^civ_tok, _}, &1)) # FIXME: I will likely need to inject each pattern here somehow…

    dbg(matcher)

    if matcher do
      # match found: drop from queue, continue on the frame with the new message
      {:noreply, %{drop_inbox(matcher, state) | stack: rst_stack},
       {:continue, dbg({cont_tok, vars, elem(matcher, 1)})}}
    else
      # No match found; keep waiting
      {:noreply, state}
    end
  end

  def handle_continue({:return, ret_val}, state) do
    dbg()
    [{:return, cont_tok, vars} | rest_stack] = state.stack
    {:noreply, %{state | stack: rest_stack},
     {:continue, {cont_tok, ret_val, vars}}}
  end

  def handle_continue({"chorex_return", ret_val, %{parent: parent_pid}}, state) do
    send(parent_pid, {:chorex_return, state.actor, ret_val})
  end

  defmacro __using__(_args) do
    quote do
      use GenServer
      alias Chorex.Runtime
      import Chorex.Runtime

      @impl true
      defdelegate init(start), to: Runtime

      @impl true
      defdelegate handle_info(msg, state), to: Runtime

      # Need to special-case these ones because they're defined by
      # Runtime. Can't use defdelegate because the impl needs to add
      # its own function clauses.
      @impl true
      def handle_continue(:try_recv, state), do: Runtime.handle_continue(:try_recv, state)
      def handle_continue({:return, _} = m, state), do: Runtime.handle_continue(m, state)
      def handle_continue({"chorex_return", _, _} = m, state), do: Runtime.handle_continue(m, state)

    end
  end
end

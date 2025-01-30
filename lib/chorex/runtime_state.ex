defmodule Chorex.RuntimeState do
  alias Chorex.Types
  alias __MODULE__

  @typedoc "An entry in the inbox looks like a CIV token × message payload"
  @type inbox_msg :: {Types.civ_tok(), msg :: any()}

  @type var_map :: %{} | %{atom() => any()}

  @type stack_frame ::
          {:recv, civ_tok :: Types.civ_tok(), match_fun :: (any() -> false | var_map()), cont_tok :: String.t(),
           vars :: var_map()}
          | {:return, cont_tok :: String.t(), vars :: var_map()}

  @type t :: %__MODULE__{
          config: nil | %{atom() => pid()},
          impl: atom(),
          session_tok: String.t(),
          vars: var_map(),
          inbox: :queue.queue(inbox_msg()),
          stack: [stack_frame()]
        }

  defstruct [:config, :actor, :impl, :session_tok, :vars, :inbox, :stack]

  @spec push_inbox(inbox_msg(), t()) :: t()
  def push_inbox(msg, %RuntimeState{} = state),
    do: %{state | inbox: :queue.cons(msg, state.inbox)}

  @spec drop_inbox(inbox_msg(), t()) :: t()
  def drop_inbox(msg, %RuntimeState{} = state),
    do: %{state | inbox: :queue.delete(msg, state.inbox)}

  @spec push_recv_frame({Types.civ_tok(), any(), String.t()}, t()) :: t()
  def push_recv_frame({civ_tok, msg_pat, cont_tok}, %RuntimeState{} = state) do
    %{state | stack: [{:recv, civ_tok, msg_pat, cont_tok, state.vars} | state.stack]}
  end

  @spec push_func_frame(String.t(), t()) :: t()
  def push_func_frame(cont_tok, %RuntimeState{} = state) do
    %{state | stack: [{:return, cont_tok, state.vars} | state.stack]}
  end

  @spec push_continue_frame(String.t(), t()) :: t()
  def push_continue_frame(cont_tok, %RuntimeState{} = state) do
    %{state | stack: [{:continue, cont_tok, state.vars} | state.stack]}
  end

  @spec push_recover_frame(String.t(), t()) :: t()
  def push_recover_frame(tok, %RuntimeState{} = state) do
    %{state | stack: [{:recover, tok} | state.stack]}
  end

  @doc """
  Drop everything up to the first `recover` frame on the stack. Return
  the recovery token as well as the state with the stack popped.
  """
  @spec pop_to_recover_frame(t()) :: {String.t(), t()}
  def pop_to_recover_frame(%RuntimeState{} = state) do
    [{:recover, token} | new_stack] =
      state.stack
      |> Enum.drop_while(fn {:recover, _tok} -> false
                            _ -> true end)

    {token, %{state | stack: new_stack}}
  end

  @doc """
  Throw away the top frame, assuming it's a recover frame. If it's
  not, raise an error.
  """
  def ditch_recover_frame(state) do
    new_stack =
      case state.stack do
        [{:recover, _tok} | rst] -> rst
        _ ->
          dbg(state.stack)
          raise "Chorex Runtime Error: unable to ditch recovery frame!"
      end

    %{state | stack: new_stack}
  end

  @spec put_var(t(), atom(), any()) :: t()
  def put_var(%RuntimeState{} = state, name, val) do
    %{state | vars: Map.put(state.vars, name, val)}
  end
end

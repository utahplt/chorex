defmodule Chorex.RuntimeState do
  alias Chorex.Types
  alias __MODULE__

  @typedoc "An entry in the inbox looks like a CIV token × message payload"
  @type inbox_msg :: {Types.civ_tok(), msg :: any()}

  @type var_map :: %{} | %{atom() => any()}

  @type stack_frame ::
          {:recv, civ_tok :: Types.civ_tok(), msg_pat :: any(), cont_tok :: String.t(),
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

  @spec push_recv_frame({Types.civ_tok(), any(), String.t(), var_map()}, t()) :: t()
  def push_recv_frame({civ_tok, msg_pat, cont_tok, vars}, %RuntimeState{} = state) do
    %{state | stack: [{:recv, civ_tok, msg_pat, cont_tok, vars} | state.stack]}
  end

  @spec push_func_frame({String.t(), var_map()}, t()) :: t()
  def push_func_frame({cont_tok, vars}, %RuntimeState{} = state) do
    %{state | stack: [{:return, cont_tok, vars} | state.stack]}
  end

  @spec put_var(t(), atom(), any()) :: t()
  def put_var(%RuntimeState{} = state, name, val) do
    %{state | vars: Map.put(state.vars, name, val)}
  end
end

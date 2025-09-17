defmodule Chorex.RuntimeState do
  alias Chorex.Types
  alias __MODULE__

  @typedoc "An entry in the inbox looks like a CIV token × message payload"
  @type inbox_msg :: {Types.civ_tok(), msg :: any()}

  @type var_map :: %{} | %{atom() => any()}

  @type stack_frame ::
          {:recv, civ_tok :: Types.civ_tok(), match_fun :: (any() -> false | var_map()),
           cont_tok :: String.t(), vars :: var_map()}
          | {:return, cont_tok :: String.t(), vars :: var_map()}

  @type t :: %__MODULE__{
          config: nil | %{atom() => pid()},
          impl: atom(),
          session_token: String.t(),
          vars: var_map(),
          inbox: :queue.queue(inbox_msg()),
          stack: [stack_frame()],
          barrier_depth: integer(),
          # holding spot when waiting for sync barrier
          waiting_value: any()
        }

  defstruct [
    :config,
    :actor,
    :impl,
    :session_token,
    :vars,
    :inbox,
    :stack,
    :barrier_depth,
    :waiting_value
  ]

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

  @spec push_recover_barrier_frames(String.t(), any(), t()) :: {t(), any()}
  def push_recover_barrier_frames(recover_tok, barrier_id, %RuntimeState{} = state) do
    d = state.barrier_depth + 1

    barrier_token =
      {:barrier, state.session_token, barrier_id, d}

    new_state =
      %{
        state
        | stack: [
            barrier_token,
            {:recover, recover_tok} | state.stack
          ],
          barrier_depth: d
      }

    {new_state, barrier_token}
  end
end

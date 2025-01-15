defmodule Chorex.Types do
  @typedoc """
    A CIV token is a string (UUID) indicating the session, the line
    information identifying the message, the sender name, and the
    receiver name.
  """
  @type civ_tok :: {String.t(), any(), atom(), atom()}

  @typedoc "A chorex message looks like the atom `:chorex`, a `civ_tok()`, and a payload"
  @type chorex_message :: {:chorex, civ_tok(), payload :: any()}

end

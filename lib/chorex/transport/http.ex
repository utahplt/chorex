defmodule Chorex.Transport.Http do
  @moduledoc """
  HTTP message transport for choreographies.
  """

  defstruct [:host, :port, :socket]

  defimpl Chorex.Transport.Backend, for: __MODULE__ do
	def send_msg(self, msgs) do
      
    end
  end
end

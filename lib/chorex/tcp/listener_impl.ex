defmodule Chorex.Tcp.ListenerImpl do
  use Chorex.Tcp.ListenerChor.Chorex, :listener

  @hardcoded_options [mode: :binary, active: false]

  def get_listener_socket(config) do
    default_options = [
      backlog: 1024,
      nodelay: true,
      send_timeout: 30_000,
      send_timeout_close: true,
      reuseaddr: true
    ]

    opts =
      Enum.uniq_by(
        @hardcoded_options ++ config[:user_options] ++ default_options,
        fn
          {key, _} when is_atom(key) -> key
          key when is_atom(key) -> key
        end
      )

    # Hopefully returns {:ok, :inet.socket()}
    :gen_tcp.listen(config[:port], opts)
    |> IO.inspect(label: "listener socket")
  end
end

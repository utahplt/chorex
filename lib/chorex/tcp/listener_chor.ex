defmodule Chorex.Tcp.ListenerChor do
  import Chorex

  defchor [Listener, AccepterPool] do
    def run(Listener.(config)) do
      Listener.get_listener_socket(config) ~> AccepterPool.({:ok, socket})
      loop(AccepterPool.(socket))
    end

    def loop(AccepterPool.(listen_socket)) do
      AccepterPool.accept_and_handle_connection(listen_socket)
      loop(AccepterPool.(listen_socket))
    end
  end
end

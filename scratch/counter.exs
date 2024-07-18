defmodule Counter do
  defmodule Chor do
    import Chorex

    defchor [Server, Client] do
      # Client.incr() ~> Server.(value)
      # Client.incr() ~> Server.(value)
      Client.incr() ~> Server.(value)
      Server.(value)
    end
  end

  defmodule MyClient do
    use Chor.Chorex, :client
    def incr(), do: 1
  end

  def kickoff() do
    pc = spawn(MyClient, :init, [[]])
    ps = spawn(MyServer, :init, [[]])

    config = %{Server => ps, Client => pc, :super => self()}

    send(pc, {:config, config})
    send(ps, {:config, config})

    # receive {:chorex_return, Server, 0}
    receive do
      {:chorex_return, Client, val} -> IO.puts("Got #{val}")
    end
    Process.sleep(1000)
  end

end

# make file kickoff.exs = Chor.Counter.kickoff()
# mix run kickoff.exs

Counter.kickoff()

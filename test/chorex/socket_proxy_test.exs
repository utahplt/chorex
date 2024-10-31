defmodule Chorex.SocketProxyTest do
  use ExUnit.Case

  defmodule BasicRemote do
    import Chorex

    defchor [SockAlice, SockBob] do
      def run(SockAlice.(report), SockBob.(report)) do
        SockAlice.("hello") ~> SockBob.(m1)
        SockAlice.("there") ~> SockBob.(m2)
        SockAlice.("bob") ~> SockBob.(m3)
        SockBob.([m1, m2, m3]) ~> SockAlice.(message)
        SockAlice.(send(report, {:done, message}))
        SockBob.(send(report, {:done, "whatever"}))
      end
    end
  end

  defmodule SockAliceImpl do
    use BasicRemote.Chorex, :sockalice
  end

  defmodule SockBobImpl do
    use BasicRemote.Chorex, :sockbob
  end

  @tag :skip
  test "basic proxy works" do
    # Spin up two tasks to collect responses
    alice_receiver = Task.async(fn ->
      m = receive do
        x -> x
      end
      m
    end)

    bob_receiver = Task.async(fn ->
      m = receive do
        x -> x
      end
      m
    end)

    Chorex.start(BasicRemote.Chorex,
      %{SockAlice => SockAliceImpl,
        SockBob => {:remote, 4242, "localhost", 4243}}, [alice_receiver, nil])

    Chorex.start(BasicRemote.Chorex,
      %{SockAlice => {:remote, 4243, "localhost", 4242},
        SockBob => SockBobImpl}, [nil, bob_receiver])

    assert {:done, ["hello", "there", "bob"]} = Task.await(alice_receiver)
    assert {:done, "whatever"} = Task.await(bob_receiver)
  end
end

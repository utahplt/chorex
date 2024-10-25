defmodule Chorex.SocketProxyTest do
  use ExUnit.Case

  defmodule BasicRemote do
    import Chorex

    defchor [Alice, Bob] do
      def run(Alice.(report), Bob.(report)) do
        Alice.("hello") ~> Bob.(m1)
        Alice.("there") ~> Bob.(m2)
        Alice.("bob") ~> Bob.(m3)
        Bob.([m1, m2, m3]) ~> Alice.(message)
        Alice.(send(report, {:done, message}))
        Bob.(send(report, {:done, message})) # this should be an error
      end
    end
  end

  defmodule AliceImpl do
    use BasicRemote.Chorex, :alice
  end

  defmodule BobImpl do
    use BasicRemote.Chorex, :bob
  end

  test "basic proxy works" do
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
      %{Alice => AliceImpl,
        Bob => {:remote, 4242, "localhost", 4243}}, [alice_receiver, nil])

    Chorex.start(BasicRemote.Chorex,
      %{Alice => {:remote, 4243, "localhost", 4242},
        Bob => BobImpl}, [nil, bob_receiver])

    assert Task.await(alice_receiver) == ["hello", "there", "bob"]
    assert Task.await(bob_receiver) == "whatever"
  end
end

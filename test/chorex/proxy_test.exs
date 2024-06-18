defmodule Chorex.ProxyTest do
  use ExUnit.Case
  doctest Chorex.Proxy
  import Chorex.Proxy

  defmodule Worker do
    def test_pingpong() do
      # driver of the test
      driver_pid = receive do
        m -> m
      end

      send(driver_pid, :worker_here)

      m2 = receive do
        m -> m
      end

      send(driver_pid, {:got, m2})
    end

    def test_actor_comm(:start) do
      receive do
        {:config, config} ->
          test_actor_comm(config)
      end
    end
    def test_actor_comm(config) do
      send(config[:super], {:chorex, Worker, config})
      send(config[Chorex.ProxyTest.Actor], {:from_worker, config[:proxy]})
      receive do
        {"hello there", actor_pid} ->
          send(config[:super], {:chorex, Worker, {:found_actor, actor_pid}})
      end
    end
  end

  defmodule Actor do
    def test_actor_comm(:start) do
      receive do
        {:config, config} ->
          test_actor_comm(config)
      end
    end
    def test_actor_comm(config) do
      send(config[:super], {:chorex, Actor, config})
      receive do
        {:from_worker, the_proxy_pid} ->
          send(config[:super], {:chorex, Actor, {:got_worker_proxy, the_proxy_pid}})
      end
      send_proxied(config[Chorex.ProxyTest.Worker], {"hello there", self()})
    end
  end

  test "proxy forwards messages" do
    {:ok, proxy} = GenServer.start(Chorex.Proxy, [])
    assert is_pid(proxy)
    begin_session(proxy, [self()], 42, Worker, :test_pingpong, [])
    send_proxied(proxy, self())
    assert_receive :worker_here
    i = :rand.uniform(1_000_000)
    send_proxied(proxy, i)
    assert_receive {:got, ^i}
  end

  test "proxy injects self into config" do
    {:ok, proxy} = GenServer.start(Chorex.Proxy, [])
    a1 = spawn(Actor, :test_actor_comm, [:start])
    begin_session(proxy, [a1, self()], 0, Worker, :test_actor_comm, [:start])
    config = %{Actor => a1, Worker => proxy, :super => self()}

    send(a1, {:config, config})
    send_proxied(proxy, {:config, config})

    assert_receive {:chorex, Actor, actor_config}
    refute Map.has_key?(actor_config, :proxy)
    assert_receive {:chorex, Worker, %{:proxy => ^proxy}}
    assert_receive {:chorex, Actor, {:got_worker_proxy, ^proxy}}
    assert_receive {:chorex, Worker, {:found_actor, ^a1}}
  end

  test "sessions kept separate" do
    {:ok, proxy} = GenServer.start(Chorex.Proxy, [])
  end
end

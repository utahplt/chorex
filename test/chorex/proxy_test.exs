defmodule Chorex.ProxyTest do
  use ExUnit.Case
  doctest Chorex.Proxy
  import Chorex.Proxy

  defmodule Worker do
    def test_pingpong() do
      # driver of the test
      driver_pid =
        receive do
          m -> m
        end

      send(driver_pid, :worker_here)

      m2 =
        receive do
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
    begin_session(proxy, [self()], Worker, :test_pingpong, [])
    send_proxied(proxy, self())
    assert_receive :worker_here
    i = :rand.uniform(1_000_000)
    send_proxied(proxy, i)
    assert_receive {:got, ^i}
  end

  test "proxy injects self into config" do
    {:ok, proxy} = GenServer.start(Chorex.Proxy, [])
    a1 = spawn(Actor, :test_actor_comm, [:start])
    begin_session(proxy, [a1, self()], Worker, :test_actor_comm, [:start])
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
    a1 = spawn(Actor, :test_actor_comm, [:start])
    begin_session(proxy, [a1, self()], Worker, :test_actor_comm, [:start])
    config1 = %{Actor => a1, Worker => proxy, :super => self()}
    send(a1, {:config, config1})
    send_proxied(proxy, {:config, config1})

    assert_receive {:chorex, Actor, actor_config}
    refute Map.has_key?(actor_config, :proxy)
    assert_receive {:chorex, Worker, %{:proxy => ^proxy}}
    assert_receive {:chorex, Actor, {:got_worker_proxy, ^proxy}}
    assert_receive {:chorex, Worker, {:found_actor, ^a1}}

    a2 = spawn(Actor, :test_actor_comm, [:start])
    begin_session(proxy, [a2], Worker, :test_actor_comm, [:start])
    config2 = %{Actor => a2, Worker => proxy, :super => self()}
    send(a2, {:config, config2})
    send(proxy, {:chorex, a2, {:config, config2}})

    assert_receive {:chorex, Actor, actor_config}
    refute Map.has_key?(actor_config, :proxy)
    assert_receive {:chorex, Worker, worker_config}
    assert %{proxy: ^proxy} = worker_config
    # make sure we have the right actor here
    assert %{Actor => ^a2} = worker_config
    assert_receive {:chorex, Actor, {:got_worker_proxy, ^proxy}}
    assert_receive {:chorex, Worker, {:found_actor, ^a2}}
  end

  defmodule StateWorker do
    def test_state(:start) do
      receive do
        {:config, config} -> test_state(config)
      end
    end

    def test_state(config) do
      receive do
        :incr ->
          update_state(config, fn x -> {x + 1, x + 1} end)
          test_state(config)

        :fetch ->
          send(config[Chorex.ProxyTest.StateClient], {:final_count, fetch_state(config)})
      end
    end
  end

  defmodule StateClient do
    def test_state(:start) do
      receive do
        {:config, config} -> test_state(config)
      end
    end

    def test_state(config) do
      bump_times =
        receive do
          {:bump, n} -> n
        end

      for _i <- 1..bump_times do
        send_proxied(config[Chorex.ProxyTest.StateWorker], :incr)
      end

      send_proxied(config[Chorex.ProxyTest.StateWorker], :fetch)

      receive do
        {:final_count, c} ->
          send(config[:super], {:got_count, c})
      end
    end
  end

  test "state shared" do
    {:ok, proxy} = GenServer.start(Chorex.Proxy, 0)

    # First session
    a1 = spawn(StateClient, :test_state, [:start])
    begin_session(proxy, [a1], StateWorker, :test_state, [:start])
    config1 = %{StateWorker => proxy, StateClient => a1, :super => self()}
    send(a1, {:config, config1})
    send(proxy, {:chorex, a1, {:config, config1}})

    # Second session
    a2 = spawn(StateClient, :test_state, [:start])
    begin_session(proxy, [a2], StateWorker, :test_state, [:start])
    config2 = %{StateWorker => proxy, StateClient => a2, :super => self()}
    send(a2, {:config, config2})
    send(proxy, {:chorex, a2, {:config, config2}})

    send(a2, {:bump, 21})
    Process.sleep(1)
    send(a1, {:bump, 21})

    final1 =
      receive do
        {:got_count, n} -> n
      end

    final2 =
      receive do
        {:got_count, n} -> n
      end

    # WARNING: this is a little brittle but it's working
    assert {21, 42} = {final1, final2}
  end
end

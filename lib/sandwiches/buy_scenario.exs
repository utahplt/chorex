{:ok, store_proxy} = GenServer.start_link(StoreProxy, :go)

customer = spawn(CustomerAlice, :init, [])

:ok =
  GenServer.call(
    store_proxy,
    {:begin_session, [customer], 42, StoreBackend, :init, [MyStoreBackendImpl]}
  )

config = %{StoreProxy => store_proxy, Customer => customer, :super => self()}
# Fake it from the customer so it gets the right session
send(store_proxy, {:chorex, customer, {:config, config}})
send(customer, {:config, config})

receive do
  m ->
    IO.inspect(m, label: "got message")
end

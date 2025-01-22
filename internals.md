Documentation of Chorex Internals
=================================

Compile time
------------

Runtime
-------

### GenServer state

An actor in a choreography is a GenServer. This documents what goes inside the running state.

The state is a map. Keys:

 - `config`
 - `impl`
 - `vars`
 - `stack`

Elements in the `stack` look like this:

```elixir
{"continuation-token-here-uuid-v4", %{var => val}}
```

Stack gets pushed when calling a function. (Search `# Application projection` in `chorex.ex` for an example.)

Example of a return can be found wherever `make_continue` is called.

### Manual startup

To start the choreography, you need to invoke the `init` function in
each of your actors (provided via the `use ...` invocation)
whereupon each actor will wait to receive a config mapping actor
name to PID:

```elixir
  the_seller = spawn(MySeller, :init, [[]])
  the_buyer1 = spawn(MyBuyer1, :init, [[]])
  the_buyer2 = spawn(MyBuyer2, :init, [[]])

  config = %{Seller1 => the_seller, Buyer1 => the_buyer1, Buyer2 => the_buyer2, :super => self()}

  send(the_seller, {:config, config})
  send(the_buyer1, {:config, config})
  send(the_buyer2, {:config, config})
```

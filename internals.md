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

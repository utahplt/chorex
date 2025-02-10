Documentation of Chorex Internals
=================================

Compile time
------------

The `Chorex` module manages actor projection.


Runtime
-------

### GenServer state

An actor in a choreography is a GenServer. All actors are made by invoking `use Chorex.Runtime`. See that module for a description of the runtime state.

Chorex - Choreographic Programming in Elixir


# Synopsis

**Note:** this documentation is current as of 2024-05-30. The project is evolving rapidly, so this README may occasionally get out-of-sync with what the project can do.

Describe the choreography in a module with the `defchor` macro:

```elixir
defmodule TestChor do
  defchor [Buyer, Seller] do
    Buyer.get_book_title() ~> Seller.(b)
    Seller.get_price(b) ~> Buyer.(p)
    Buyer.(p)
  end
end

```

Implement the actors:

```elixir
defmodule MyBuyer do
  use TestChor.Chorex, :buyer

  def get_book_title(), do: "Das Glasperlenspiel"
end

defmodule MySeller do
  use TestChor.Chorex, :seller

  def get_price(_b), do: 42
end
```

Elsewhere in your program:

```elixir
ps = spawn(MySeller, :init, [])
pb = spawn(MyBuyer, :init, [])

config = %{Seller => ps, Buyer => pb, :super => self()}

send(ps, {:config, config})
send(pb, {:config, config})

receive do
  {:chorex_return, Buyer, val} -> IO.puts("Got #{val}")
end
```

The program should print `Got 42` to the terminal.


# Description

Chorex is a library for *choreographic programming* in Elixir. Choreographic programming is a programming paradigm where you specify the interactions between different entities in a concurrent system in one global view, and then *extract implementations* for each of those actors. See [§ Bibliography](#org44e5aee) for references on choreographic programming in general.


## Installation

Chorex is available on Hex.pm. Install by including the following in your `mix.exs` file under the `deps` list:

```elixir
def deps do
  [
    ...,
    {:chorex, "~> 0.1.0"},
    ...
  ]
end
```

You can install development versions of Chorex directly from GitHub like so:

```elixir
def deps do
  [
    ...,
    {:chorex, github: "utahplt/chorex"},
    ...
  ]
end
```

Note that this is *experimental software* and stuff *will* break. Please don&rsquo;t rely on this for anything production-grade. Not yet at least.


## What is a choreography?

A choreography is a birds-eye view of an interaction between nodes in a distributed system. You have some set of *actors/—in Elixir parlance processes—that exchange /messages* while also running some /local computation/—i.e. functions that don&rsquo;t rely on talking to other nodes in the system.


### Choreography syntax

Chorex introduces some new syntax for choreographies. Here&rsquo;s a breakdown of how it works:

```elixir
defchor [Actor1, Actor2, ...] do
  ...choreography body...
end
```

The `defchor` macro wraps a choreography and translates it into core Elixir code. You give `defchor` a list of actors, specified as if they were module names, and then a `do` block wraps the choreography body.

```elixir
Actor1.(var1) ~> Actor2.(var2_a)
Actor1.func_1() ~> Actor2.(var2_b)
Actor1.func_2(var1_a, var1_b) ~> Actor2.(var2_c)
Actor1.(var1_a + var1_b) ~> Actor2.(var2_c)
```

The `~>` indicates sending a message between actors. The left-hand-side must be `Actor1.<something>`, where that `<something>` bit can be one of three things:

1.  A variable local to Actor1
2.  A function local to Actor1 (with or without arguments, also all local to Actor1)
3.  An expression local to Actor1

The right-and-side must be `Actor2.<var_name>`. This means that the left-hand-side will be computed on `Actor1` and send to `Actor2` where it will be stored in variable `<var_name>`.

**ACHTUNG!! `mix format` will rewrite `Actor1.var1` to `Actor1.var1()` which is a function call instead of a variable! Wrap variables in parens like `Actor1.(var1)` if you want to use `mix format`!** This is an unfortunate drawback—suggestions on fixing this would be welcome.

Local functions are not defined as part of the choreography; instead, you implement these in a separate Elixir module. More on that later.

```elixir
if Actor1.make_decision() do
  Actor1[L] ~> Actor2
  ...
else
  Actor1[R] ~> Actor2
  ...
end
```

`if` expressions are supported. Some actor makes a choice of which branch to go down. It is then *crucial* (and, at this point, entirely up to the user) that that deciding actor inform all other actors about the choice of branch with the special `ActorName[L] ~> OtherActorName` syntax. Note the lack of `.` and variable names. Furthermore, the true branch is always `L` (left) and the false branch is always `R` (right).

```elixir
def higher_order_chor(other_chor) do
  ... other_chor.(...) ...
end
```

Chorex supports higher-order choreographies. These are choreographies that take another choreography as an argument where it can be applied like a function.

```elixir
def some_local_chor(Actor.(var_name)) do
  Actor.(var_name) ~> OtherActor.(other_var)
  OtherActor.(other_var)
end
```

This creates a choreography that can be passed as an argument to the `higher_order_chor` function. This takes as an argument a variable living at a particular actor, and returns another value on a potentially different node.

You would combine the choreographies like so:

```elixir
defchor [Actor, OtherActor] do
  def higher_order_chor(other_chor) do
    ... other_chor.(...) ...
  end

  def some_local_chor(Actor.(var_name)) do
    Actor.(var_name) ~> OtherActor.(other_var)
    OtherActor.(other_var)
  end

  higher_order_chor(&some_local_chor/1)
end
```

Right now these functions are limited to a single argument.

```elixir
with OtherActor.(other_var) <- other_chor.(Actor.(var)) do
  ...
end
```

You can use `with` to bind a variable to the result of calling a higher-order choreography. Note that right now you can only have one `<-` in the expression.


## Creating a choreography

To create a choreography, start by making a module, and writing the choreography with the `defchor` macro.

```elixir
defmodule Bookstore do
  defchor [Actor1, Actor2] do
    Actor1.(... some expr ...) ~> Actor2.(some_var)
    Actor2.some_computation(some_var) ~> Actor1.(the_result)
    ...
  end
end
```

You will need to make a module for every actor you specify at the beginning of `defchor` and mark which actor you&rsquo;re implementing like so:

```elixir
defmodule MyFirstActor do
  use Bookstore.Chorex, :actor1

  ...
end

defmodule MySecondActor do
  use Bookstore.Chorex, :actor2

  def some_computation(val), do: ...
end
```

These modules will need to implement all of the local functions specified in the choreography. Chorex will use Elixir&rsquo;s behaviour mechanism to warn you if you don&rsquo;t implement every function needed. In the above example, the `MySecondActor` implements the role of `Actor2` in the choreography, and therefore needs to implement the `some_computation` function.

**Note:** *Actor names do not need to be the same as the modules implementing them!* It is *useful* to do that, but there exist instances where you might want to write one choreography and implement it in different ways.


## Running a choreography

To fire off the choreography, you need to spin up a process for each actor and then tell each actor where to find the other actors in the system. For the above example, you could do this:

```elixir
first_actor = spawn(MyFirstActor, :init, [])
second_actor = spawn(MySecondActor, :init, [])

config = %{Actor1 => first_actor, Actor2 => second_actor, :super => self()}
send(first_actor, config)
send(second_actor, config)
```

Once the actors are done, they will send the last value they computed to `:super` tagged with the actor they were implementing. So, for this example, you could see what `Actor1` computed by awaiting:

```elixir
receive do
  {:chorex_return, Actor1, val} -> IO.inspect(val, label: "Actor1's return: ")
end
```


## Using a choreography with the rest of your project

The local functions are free to call any other code you have—they&rsquo;re just normal Elixir. If that code sends and receives messages not managed by the choreography library, there is no guarantee that this will be deadlock-free.


# Development


## Changelog

We will collect change descriptions here until we come up with a more stable format when changes get bigger.

 - v0.2.0; (current)
 
   Add shared-state actors.

 - v0.1.0; 2024-05-30
    
   Initial release. Lots of rough edges so please, be patient. :)


## High-level internals

The `defchor` macro is implemented in the `Chorex` module.

-   The `defchor` macro gathers a list of actors.
-   For each actor, call `project` on the body of the choreography. The `project` function keeps track of the current actor as the &ldquo;label&rdquo; variable. (This vernacular borrowed from the academic literature.)
-   The functions `project` and `project_sequence` are mutually recursive: `project_sequence` gets invoked whenever `project` encounters a block with multiple instructions.
-   The `project` function walks the AST, it gathers a list of functions that will need to be implemented by each actor&rsquo;s implementing module, as well as a list of top-level functions for each projection.
    -   This gathering is handled by the `WriterMonad` module, which provides the `monadic do ... end` form as well as `return` and `mzero`.
-   Finally the macro generates modules for each actor under the `Chorex` module it generates.

So, for example, if you have a simple Choreography like this:

```elixir
defchor [Alice, Bob] do
  Alice.pick_modulus() ~> Bob.(m)
  Bob.gen_key(m) ~> Alice.(bob_key)
  Alice.encrypt(message, bob_key)
end
```

This will get transformed into (roughly) this code:

```elixir
defmodule Chorex do
  (
    def alice do
      quote do
        import Alice
        @behaviour Alice
        def init() do
          Alice.init(__MODULE__)
        end
      end
    end

    defmodule Alice do
      @callback encrypt(any(), any()) :: any()
      @callback pick_modulus() :: any()
      def init(impl) do
        receive do
          {:config, config} ->
            ret = run_choreography(impl, config)
            send(config[:super], {:chorex_return, Alice, ret})
        end
      end

      def run_choreography(impl, config) do
        if function_exported?(impl, :run_choreography, 2) do
          impl.run_choreography(impl, config)
        else
          send(config[Bob], impl.pick_modulus())

          (
            bob_key =
              receive do
                msg -> msg
              end

            impl.encrypt(message, bob_key)
          )
        end
      end
    end
  )

  (
    def bob do
      quote do
        import Bob
        @behaviour Bob
        def init() do
          Bob.init(__MODULE__)
        end
      end
    end

    defmodule Bob do
      @callback gen_key(any()) :: any()
      def init(impl) do
        receive do
          {:config, config} ->
            ret = run_choreography(impl, config)
            send(config[:super], {:chorex_return, Bob, ret})
        end
      end

      def run_choreography(impl, config) do
        if function_exported?(impl, :run_choreography, 2) do
          impl.run_choreography(impl, config)
        else
          m =
            receive do
              msg -> msg
            end

          send(config[Alice], impl.gen_key(m))
        end
      end
    end
  )

  defmacro __using__(which) do
    apply(__MODULE__, which, [])
  end
end
```

You can see there&rsquo;s a `Chorex.Alice` module and a `Chorex.Bob` module.


## Testing

Simply clone the repository and run `mix test`.


<a id="org44e5aee"></a>

# Bibliography

-   Hirsch & Garg (2022-01-16) *Pirouette: Higher-Order Typed Functional Choreographies*, Proceedings of the ACM on Programming Languages. <https://doi.org/10.1145/3498684>

-   Lugović & Montesi (2023-10-15) *Real-World Choreographic Programming: Full-Duplex Asynchrony and Interoperability*, The Art, Science, and Engineering of Programming. <https://doi.org/10.22152/programming-journal.org/2024/8/8>


# Authors

This is a project by the [Utah PLT](https://github.com/utahplt) group. Primary development by [Ashton Wiersdorf](https://lambdaland.org).

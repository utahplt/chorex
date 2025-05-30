Chorex - Choreographic Programming in Elixir

[![Chorex Tests](https://github.com/utahplt/chorex/actions/workflows/elixir.yml/badge.svg)](https://github.com/utahplt/chorex/actions/workflows/elixir.yml)

# Synopsis

**Note:** this documentation is current as of 2025-02-24. The project is evolving rapidly, so this README may occasionally get out-of-sync with what the project can do.

Add `Chorex.Registry` to your application setup:

```elixir
# part of application startup; e.g. in a Phoenix application this
# would be in MyApp.Application located at lib/my_app/application.ex
children = [
  {Registry, name: Chorex.Registry, keys: :unique}
]
```

Describe the choreography in a module with the `defchor` macro:

```elixir
defmodule TestChor do
  defchor [Buyer, Seller] do
    def run(Buyer.(book_title)) do
      Buyer.(book_title) ~> Seller.(b)
      Seller.get_price(b) ~> Buyer.(p)
      Buyer.(p)
    end
  end
end
```

Implement the actors:

```elixir
defmodule MyBuyer do
  use TestChor.Chorex, :buyer
end

defmodule MySeller do
  use TestChor.Chorex, :seller

  def get_price("Das Glasperlenspiel"), do: 42
  def get_price("A Tale of Two Cities"), do: 16
end
```

Elsewhere in your program:

```elixir
Chorex.start(TestChor.Chorex, %{Seller => MySeller, Buyer => MyBuyer}, ["Das Glasperlenspiel"])

receive do
  {:chorex_return, Buyer, val} ->
    IO.puts("Got #{val}")            # prints "Got 42"
end

Chorex.start(TestChor.Chorex, %{Seller => MySeller, Buyer => MyBuyer}, ["A Tale of Two Cities"])

receive do
  {:chorex_return, Buyer, val} ->
    IO.puts("Got #{val}")            # prints "Got 16"
end
```

# Description

Chorex is a library for *choreographic programming* in Elixir. Choreographic programming is a programming paradigm where you specify the interactions between different entities in a concurrent system in one global view, and then *extract implementations* for each of those actors. See [§ Bibliography](#org44e5aee) for references on choreographic programming in general.


## Installation

Chorex is available on Hex.pm. Install by including the following in your `mix.exs` file under the `deps` list:

```elixir
def deps do
  [
    ...,
    {:chorex, "~> 0.8.0"},
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

Add `Chorex.Registry` to your application setup:

```elixir
# part of application startup; e.g. in a Phoenix application this
# would be in MyApp.Application located at lib/my_app/application.ex
children = [
  {Registry, name: Chorex.Registry, keys: :unique}
]
```

Note that this is *experimental software* and stuff *will* break. Please don't rely on this for anything production-grade. Not yet at least.


## What is a choreography?

A choreography is a birds-eye view of an interaction between nodes in a distributed system. You have some set of *actors*—in Elixir parlance processes—that exchange *messages* while also running some *local computation*—i.e. functions that don't rely on talking to other nodes in the system.

Lindsey Kuper's research group has put together [a delightful zine explaining choreographic programming](https://decomposition.al/zines/#communicating-chorrectly-with-a-choreography). Check that out if you are new to choreographies.

At a high-level, Chorex lets you build choreographies to describe different interactions between components of your system. Chorex focuses on the communication flow; you still implement the computation that runs locally on each node, but you don't have to worry about writing `send`s between nodes.

<!-- FIXME: link the examples repo here -->
Once you have a choreography, you can *instantiate* it any number of times as you like. You might want, for example, to have one choreography describing how a user actor would communicate to create an account on a system, and then another choreography for how an existing user would log in with previously established credentials.


## Choreography syntax

Chorex introduces some new Elixir syntax for choreographies. Here's a breakdown of how it works.

Start by creating a module to hold the choreography, say `import Chorex`, and add a `defchor` block:

```elixir
defmodule MyCoolChoreography do
  import Chorex

  defchor [Actor1, Actor2, ...] do
    ...choreography body...
  end
end
```

(Note: in addition to the choreography definition here, you will need to make a module for each actor. We'll focus on the special syntax of the `defchor` block in this section, but later you'll see how to built a module for each of the `Actor1`, `Actor2`, etc.)

The `defchor` macro wraps a choreography and translates it into core Elixir code. You give `defchor` a list of actors, specified as if they were module names, and then a `do` block wraps the choreography body.

The body of the choreography is a set of functions. One function named `run` must be present: this serves as the entry point into the choreography. The arguments to `run` come from the third argument to the `Chorex.start` function and are how you typically get values into an instantiation of a choreography. (More on `Chorex.start` and function parameters in a minute.)

```elixir
defchor [Actor1, Actor2, ...] do
  def some_func(...) do
    ...
  end

  def run() do
    ...
  end
end
```


### Message passing expressions

Inside the body of functions you can write message passing expressions. Examples:

```elixir
Actor1.(var1) ~> Actor2.(var2_a)
Actor1.func_1() ~> Actor2.(var2_b)
Actor1.func_2(var1_a, var1_b) ~> Actor2.(var2_c)
Actor1.(var1_a + var1_b) ~> Actor2.(var2_c)
```

Formal syntax:

```bnf
  message_pass ::= $local_exp ~> $actor.($pat)

  local_exp    ::= $actor.($pat)
                 | $actor.$func($exp, ...)
                 | $actor.($exp)

  actor        ::= Module name         (e.g. Actor)
  func         ::= Function name       (e.g. frobnicate(...))
  pat          ::= Pattern match expr  (e.g. a variable like `foo` or tuples `{:ok, bar}` etc.)
  exp          ::= Elixir expression   (e.g. foo + sum([1, 2, 3]))
```

The `~>` indicates sending a message between actors. The left-hand-side must be `Actor1.<something>`, where that `<something>` bit can be one of three things:

1.  A variable local to Actor1
2.  A function local to Actor1 (with or without arguments, also all local to Actor1)
3.  An expression local to Actor1

The right-and-side must be `Actor2.(<pattern>)`. This means that the left-hand-side will be computed on `Actor1` and send to `Actor2` where it will be matched against the pattern `pattern`.


### Local expressions

*Local expressions* are computations that happen on a single node. These computations are isolated from each other—i.e. every location has its own variables. For example, if I say:

```elixir
defchor [Holmes, Watson] do
  def discombobulate(Holmes.(clue)) do
    ...
  end
end
```

Then inside the body of that function, I can talk about the variable `clue` which is located on the `Holmes` node. I can't, for instance, talk about the variable `clue` on the `Watson` node.

```elixir
Holmes.(clue + 1)    # fine
Watson.(clue * 2)    # error: variable `clue` not defined
```

I can *send* the value in Holmes' `clue` variable to Watson, at which point Watson can do computation with the value:

```elixir
Holmes.(clue) ~> Watson.(holmes_observes)

if Watson.remember(holmes_observes) do
  ...
else
  ...
end
```

The `remember` function here will be defined on the the implementation for the `Watson` actor.

**ACHTUNG!! `mix format` will rewrite `Actor1.var1` to `Actor1.var1()` which is a function call instead of a variable! Wrap variables in parens like `Actor1.(var1)` if you want to use `mix format`!** This is an unfortunate drawback—suggestions on fixing this would be welcome.

Local functions are not defined as part of the choreography; instead, you implement these in a separate Elixir module. More on that later.


### `if` expressions and knowledge of choice broadcasting

```elixir
if Actor1.make_decision(), notify: [Actor2] do
  ...
else
  ...
end
```

`if` expressions are supported. Some actor makes a choice of which branch to go down. It is then *crucial* that that deciding actor inform all other actors about the choice of branch with the special `notify: [Actor2, Actor3, ...]` syntax. If this is omitted, *all* actors will be informed, which may lead to more messages being sent than necessary.


### Function syntax

```elixir
defchor [Alice, Bob] do
  def run(Alice.(msg)) do
    with Bob.({pub, priv}) <- Bob.gen_key() do
      Bob.(pub) ~> Alice.(key)
      exchange_message(Alice.encrypt(msg <> "\n  love, Alice", key), Bob.(priv))
    end
  end

  def exchange_message(Alice.(enc_msg), Bob.(priv)) do
    Alice.(enc_msg) ~> Bob.(enc_msg)
    Alice.(:letter_sent)
    Bob.decrypt(enc_msg, priv)
  end
end
```

Choreographies support functions and function calls—even recursive ones. Function parameters need to be annotated with the actor they live at, and the arguments when calling the function need to match. Calling a function with the wrong actor will result in the parameter getting `nil`. E.g. calling `exchange_message` above like so will not work properly:

```elixir
exchange_message(Bob.(msg), Alice.(priv))
```

(and not just because the variables are wrong—the actor names don't match so the parameters won't get the values they need).


### Higher-order choreographies

```elixir
def higher_order_chor(other_chor) do
  ... other_chor.(...) ...
end
```

Chorex supports higher-order choreographies. This means you can pass the functions defined *inside the `defchor` block* around as you would with functions. Higher-order choreographic functions *don't* get an actor prefix and you call them as you would a function bound to a variable, like so:

```elixir
defchor [Actor, OtherActor] do
  def higher_order_chor(other_chor) do
    ... other_chor.(...) ...
  end

  def some_local_chor(Actor.(var_name)) do
    Actor.(var_name) ~> OtherActor.(other_var)
    OtherActor.(other_var)
  end

  def run() do
    higher_order_chor(@some_local_chor/1)
  end
end
```

Note that when referring to the function, you **must** use the `@func_name/3` syntax—the Chorex compiler notices the `@` and processes the function reference differently. This is because the functions defined with `def` inside the `defchor` block have private internal details (when Chorex builds them, they get special implicit arguments added) and Chorex needs to handle references to these functions specially.


### Variable binding

```elixir
with OtherActor.(other_var) <- other_chor.(Actor.(var)) do
  ...
end
```

You can bind the result of some expression to a variable/pattern at an actor with `with`. In the case of a higher-order choreography (seen above) this is whatever was on node `OtherActor` when `other_chor` executed. You may also use `with` for binding local expressions, as seen in the `exchange_message` example under § Function syntax.


### Error recovery

```elixir
defmodule Bookstore do
  import Chorex

  defchor [Buyer, Seller, Contributor] do
    def run() do
      Buyer.get_book_title() ~> Seller.(book)
      Seller.get_price(book) ~> Buyer.(price)
      Seller.get_price(book) ~> Contributor.(price)

      try do
        Contributor.compute_contribution(price) ~> Buyer.(extra_money) # might blow up

        if Buyer.in_budget(price - extra_money) do
          ...
        else
          ...
        end
      rescue
        if Buyer.in_budget(price) do # no extra money!
          Buyer.("thanks anyway") ~> Contributor.(thank_you_note)
          ...
        else
          ...
        end
      end
    end
  end
end
```

Chorex supports exceptions in the form of actors crashing. In the above example, suppose the function `compute_contribution` is known to possibly crash at runtime. In accordance with the Erlang/Elixir philosophy of "let it crash", suppose we would rather recover from this crash than harden the `Contributor` actor to prevent crashes.

In the case of a crash inside the `try` block, the crasher will get restarted, and all actors will abort execution of the `try` block and move to the `rescue` block.


## Creating a choreography: `defchor` + actor implementations

To create a choreography, start by making a module, and writing the choreography with the `defchor` macro.

```elixir
defmodule Bookstore do
  import Chorex

  defchor [Actor1, Actor2] do
    def run() do
      Actor1.(... some expr ...) ~> Actor2.(some_var)
      Actor2.some_computation(some_var) ~> Actor1.(the_result)
      ...
    end
  end
end
```

You will need to make a module for every actor you specify at the beginning of `defchor` and mark which actor you're implementing like so:

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

These modules will need to implement all of the local functions specified in the choreography. Chorex will use Elixir's behaviour mechanism to warn you if you don't implement every function needed. In the above example, the `MySecondActor` implements the role of `Actor2` in the choreography, and therefore needs to implement the `some_computation` function.

**Note:** *Actor names do not need to be the same as the modules implementing them!* It is *useful* to do that, but there exist instances where you might want to write one choreography and implement it in different ways.


## Running a choreography

You need three things to fire off a choreography:

1. The choreography description
2. An implementation for each of the actors
3. A call to `Chorex.start`

Use the `Chorex.start/3` function to start a choreography:

```elixir
Chorex.start(MyChoreography.Chorex,
             %{ Actor1 => MyActor1Impl,
                Actor2 => MyActor2Impl },
             [args, to, run])
```

The arguments are as follows:

 1. The name of the `Chorex` module to use. (The `defchor` macro creates this module for you; in the above example there is a `MyChoreography` module with a top-level `defchor` declaration that creates the `Chorex` submodule on expansion.)
 2. A map from actor name to implementation module name.
 3. A list of arguments to the `run` function in the Choreography. These will automatically get sent to the right nodes.

Once the actors are done, they will send the last value they computed to the current process tagged with the actor they were implementing. So, for this example, you could see what `Actor1` computed by awaiting:

```elixir
receive do
  {:chorex_return, Actor1, val} -> IO.inspect(val, label: "Actor1's return: ")
end
```


## Using a choreography with the rest of your project

The local functions are free to call any other code you have—they're just normal Elixir. If that code sends and receives messages not managed by the choreography library, there is no guarantee that this will be deadlock-free.


# Development

Chorex is under active development and things will change and break rapidly.

If you find any bugs or would like to suggest a feature, please [open an issue on GitHub](https://github.com/utahplt/chorex/issues).

## Changelog

We will collect change descriptions here until we come up with a more stable format when changes get bigger.

 - v0.8.13, 2025-05-30

   Recovering unwinds all the way up to corresponding barrier.

 - v0.8.12, 2025-05-30

   Bug fixes around variables and continuation frames.

 - v0.8.11, 2025-05-30

   Don't store actor's mailbox.

 - v0.8.10, 2025-05-02

   Monitor sets barrier map all to `false` instead of deleting entirely. (See v0.8.5 for when this happened.)

 - v0.8.9, 2025-05-01

   Minor fix for v0.8.8 when trying to manually expand quoted syntax involving higher-order variables.

 - v0.8.8, 2025-04-30

   Higher-order variables can be passed to other functions.

 - v0.8.7, 2025-04-29

   Actors terminate with status `:normal` when the choreography is finished.

 - v0.8.6, 2025-04-28

   Fix bug in runtime monitor where map of waiting actors was not cleared out.

 - v0.8.5, 2025-04-23

   Fix a hidden bug in the fix for v0.8.3.

 - v0.8.4, 2025-04-15

   Bug fix; typo

 - v0.8.3, 2025-04-11

   Bug fix with certain `try/rescue` patterns; barrier tokens now include stack depth.

 - v0.8.2, 2025-02-28

   Bug fix with some function parameters not making it into the context before `try/rescue` checkpoint.

 - v0.8.1, 2025-02-24

   `with` blocks can be in non-tail position. Compile error on missing branch broadcast.

 - v0.8.0, 2025-02-10

   Error recovery. 🎉 First-ever in a choreographic system! 🎉

 - v0.7.0, 2025-01-22

   New runtime model.

 - v0.6.0, 2025-01-09

   Big rewrite to project actors to GenServers under the hood.

 - v0.5.0, 2025-11-15

   Protection against out-of-order messages with communication integrity tokens.

 - v0.4.3; 2024-08-13

   Multi-clause `with` blocks work.

 - v0.4.2; 2024-08-07

   Bugfix: projecting local expressions that call out to an Erlang module.

 - v0.4.1; 2024-08-01

   Bugfix: choreographies can now have literal maps in local expressions.

 - v0.4.0; 2024-08-01

   Functions can take arbitrary number of arguments from different actors.

 - v0.3.1; 2024-07-30

   Fix many problems around local expression projection.

 - v0.3.0; 2024-07-22

   Add `Chorex.start` and `run` function as an entry-point into the choreography.

 - v0.2.0; 2024-07-03

   Add shared-state actors.

 - v0.1.0; 2024-05-30

   Initial release. Lots of rough edges so please, be patient. :)


## High-level internals

The `defchor` macro is implemented in the `Chorex` module.

-   The `defchor` macro gathers a list of actors.
-   For each actor, call `project` on the body of the choreography. The `project` function keeps track of the current actor as the `label` variable. (This vernacular borrowed from the academic literature.)
-   The functions `project` and `project_sequence` are mutually recursive: `project_sequence` gets invoked whenever `project` encounters a block with multiple instructions.
-   The `project` function walks the AST, it gathers a list of functions that will need to be implemented by each actor's implementing module, as well as a list of top-level functions for each projection.
    -   This gathering is handled by the `WriterMonad` module, which provides the `monadic do ... end` form as well as `return` and `mzero`.
-   Finally the macro generates modules for each actor under the `Chorex` module it generates.


Each actor projects to GenServer. The GenServer maintains some state at runtime: most importantly, it tracks the function call stack and an inbox of pending Chorex messages.


## Testing

Simply clone the repository and run `mix test`.


<a id="org44e5aee"></a>

# Bibliography

-   Hirsch & Garg (2022-01-16) *Pirouette: Higher-Order Typed Functional Choreographies*, Proceedings of the ACM on Programming Languages. <https://doi.org/10.1145/3498684>

-   Lugović & Montesi (2023-10-15) *Real-World Choreographic Programming: Full-Duplex Asynchrony and Interoperability*, The Art, Science, and Engineering of Programming. <https://doi.org/10.22152/programming-journal.org/2024/8/8>


# Authors

This is a project by the [Utah PLT](https://github.com/utahplt) group. Primary development by [Ashton Wiersdorf](https://lambdaland.org).

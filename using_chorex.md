Using Chorex
============

Make your modules dance!

Chorex allows you to specify a choreography: a birds-eye view of an
interaction of concurrent parties. Chorex takes that choreography
creates a *projection* of that interaction for each party in the
system.

Take, for example, the classic problem of a book seller and two
buyers who want to split the price. The interaction looks like this:

```
+------+         +------+ +------+
|Buyer1|         |Seller| |Buyer2|
+--+---+         +--+---+ +--+---+
   |                |        |
   |   Book title   |        |
   |--------------->|        |
   |                |        |
   |     Price      |        |
   |<---------------|        |
   |                |        |
   |                |  Price |
   |                |------->|
   |                |        |
   |      Contribution       |
   |<------------------------|
   |                |        |
   |   Buy/No buy   |        |
   |--------------->|        |
   |                |        |
   |(if Buy) address|        |
   |--------------->|        |
   |                |        |
   | Shipping date  |        |
   |<---------------|        |
   |                |        |
+--+---+         +--+---+ +--+---+
|Buyer1|         |Seller| |Buyer2|
+------+         +------+ +------+
```

You can encode that interaction with the `defchor` macro and DSL:

```elixir
defmodule ThreePartySeller do
  defchor [Buyer1, Buyer2, Seller] do
    def run() do
      Buyer1.get_book_title() ~> Seller.(b)
      Seller.get_price("book:" <> b) ~> Buyer1.(p)
      Seller.get_price("book:" <> b) ~> Buyer2.(p)
      Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

      if Buyer1.(p - contrib < get_budget()) do
        Buyer1[L] ~> Seller
        Buyer1.get_address() ~> Seller.(addr)
        Seller.get_delivery_date(b, addr) ~> Buyer1.(d_date)
        Buyer1.(d_date)
      else
        Buyer1[R] ~> Seller
        Buyer1.(nil)
      end
    end
  end
end
```

The `defchor` macro will take care of generating code that handles
sending messages. Now all you have to do is implement the local
functions that don't worry about the outside system:

```elixir
defmodule MySeller do
  use ThreePartySeller.Chorex, :seller

  def get_price(book_name), do: ...
  def get_delivery_date(book_name, addr), do: ...
end

defmodule MyBuyer1 do
  use ThreePartySeller.Chorex, :buyer1

  def get_book_title(), do: ...
  def get_address(), do: ...
  def get_budget(), do: ...
end

defmodule MyBuyer2 do
  use ThreePartySeller.Chorex, :buyer2

  def compute_contrib(price), do: ...
end
```

What the `defchor` macro actually does is creates a module `Chorex`
and submodules for each of the actors: `Chorex.Buyer1`,
`Chorex.Buyer2` and `Chorex.Seller`. There's a handy `__using__`
macro that will Do the right thing when you say `use Mod.Chorex, :actor_name`
and will import those modules and say that your module implements
the associated behaviour. That way, you should get a nice
compile-time warning if a function is missing.

## Starting a choreography

Invoke `Chorex.start/3` with:

1. The module name of the choreography,
2. A map from actor name to implementation name, and
3. A list of initial arguments.

So, you could start the choreography from the previous section with:

```elixir
Chorex.start(ThreePartySeller.Chorex,
             %{ Buyer1 => MyBuyer1,
                Buyer2 => MyBuyer2,
                Seller => MySeller },
             [])
```

## Choreography return values

Each of the parties will try sending the last value they computed
once they're done running. These messages will get set to whatever
process kicked the the choreography off.

```elixir
Chorex.start(ThreePartySeller.Chorex,
             %{ Buyer1 => MyBuyer1,
                Buyer2 => MyBuyer2,
                Seller => MySeller },
             [])

receive do
  {:chorex_return, Buyer1, d_date} -> report_delivery(d_date)
end
```

## Higher-order choreographies

Chorex supports higher-order choreographies. For example, you can
define a generic buyer/seller interaction and abstract away the
decision process into a higher-order choreography:

```elixir
defmodule TestChor3 do
  defchor [Buyer3, Contributor3, Seller3] do
    def bookseller(decision_func) do
      Buyer3.get_book_title() ~> Seller3.the_book
      with Buyer3.decision <- decision_func.(Seller3.get_price("book:" <> the_book)) do
        if Buyer3.decision do
          Buyer3[L] ~> Seller3
          Buyer3.get_address() ~> Seller3.the_address
          Seller3.get_delivery_date(the_book, the_address) ~> Buyer3.d_date
          Buyer3.d_date
        else
          Buyer3[R] ~> Seller3
          Buyer3.(nil)
        end
      end
    end

    def one_party(Seller3.(the_price)) do
      Seller3.(the_price) ~> Buyer3.(p)
      Buyer3.(p < get_budget())
    end

    def two_party(Seller3.(the_price)) do
      Seller3.(the_price) ~> Buyer3.(p)
      Seller3.(the_price) ~> Contributor3.(p)
      Contributor3.compute_contrib(p) ~> Buyer3.(contrib)
      Buyer3.(p - contrib < get_budget())
    end

    def run(Buyer3.(get_contribution?)) do
      if Buyer3.(get_contribution?) do
        Buyer3[L] ~> Contributor3
        Buyer3[L] ~> Seller3
        bookseller(@two_party/1)
      else
        Buyer3[R] ~> Contributor3
        Buyer3[R] ~> Seller3
        bookseller(@one_party/1)
      end
    end
  end
end
```

Notice the `@two_part/1` syntax: the `@` is necessary so Chorex
knows that this is a reference to a function defined inside the
`defchor` block; it needs to handle these references specially.

Now, when you start up the choreography, the you can instruct the
choreography whether or not to run the three-party scenario. The
first item in the list of arguments will get sent to the node
running the `Buyer3` behaviour and will be used in the decision
process inside the `run` function.

```elixir
Chorex.start(TestChor3.Chorex, %{ ... }, [true])  # run 3-party
Chorex.start(TestChor3.Chorex, %{ ... }, [false]) # run 2-party
```

### **Experimental** TCP transport setup

You can run choreographies over TCP. Instead of specifying the
implementing module's name in the actor ↦ module map, put a tuple
like `{:remote, local_port, remote_host, remote_port}`. A process
will begin listening on `local_port` and forward messages to the
proper actors on the current node. Messages going to a remote actor
will be buffered until a TCP connection is established, at which
point they'll be sent FIFO.

Example with hosts `alice.net` and `bob.net`:

Host `alice.net`:

```elixir
Chorex.start(BasicRemote.Chorex,
  %{SockAlice => SockAliceImpl,
    SockBob => {:remote, 4242, "bob.net", 4243}}, [])
```

Host `bob.net`:

```elixir
Chorex.start(BasicRemote.Chorex,
  %{SockAlice => {:remote, 4243, "alice.net", 4242},
    SockBob => SockBobImpl}, [])
```

**WARNING** this transport is *experimental* and not guaranteed to
work. We've had issues with message delivery during testing. PRs welcome!

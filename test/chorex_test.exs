defmodule ChorexTest do
  use ExUnit.Case
  doctest Chorex
  import Chorex

  # quote do
  #   defchor [Buyer, Seller] do
  #     def run() do
  #       Seller.(3 * 4)
  #       Buyer.(1 + 2)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  # quote do
  #   defchor [Buyer, Seller] do
  #     def run() do
  #       Buyer.get_book_title() ~> Seller.(b)
  #       Seller.get_price("book:" <> b) ~> Buyer.(p)
  #       Seller.("book:" <> b)
  #       Buyer.(p + 2)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule TestChor do
    defchor [Buyer, Seller] do
      def run() do
        Buyer.get_book_title() ~> Seller.(b)
        Seller.get_price("book:" <> b) ~> Buyer.(p)
        Seller.(:done)
        Buyer.(p + 2)
      end
    end
  end

  defmodule MyBuyer do
    use TestChor.Chorex, :buyer

    def get_book_title(), do: "Das Glasperlenspiel"
  end

  defmodule MySeller do
    use TestChor.Chorex, :seller

    def get_price("book:Das Glasperlenspiel"), do: 40
    def get_price("Das Glasperlenspiel"), do: 39
    def get_price(_), do: 0
  end

  test "module compiles" do
    # If we see this, the choreography compiled!
    assert 40 + 2 == 42
  end

  test "choreography runs" do
    Chorex.start(
      TestChor.Chorex,
      %{Buyer => MyBuyer, Seller => MySeller},
      []
    )

    assert_receive {:chorex_return, Buyer, 42}
    assert_receive {:chorex_return, Seller, :done}
  end

  # {:ok, fh} = File.open("diagnostics.ex", [:write])

  # quote do
  #   defchor [Buyer1us, Seller1us] do
  #     def run() do
  #       Buyer1us.get_book_title() ~> Seller1us.(b)
  #       Seller1us.get_price("book:" <> b) ~> Buyer1us.(p)
  #       Buyer1us.(:whatever) ~> Seller1us.(wat)
  #       Seller1us.order_book(b, wat)
  #       Buyer1us.(p + 2)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule TestChor1Civ do
    defchor [Buyer1civ, Seller1civ] do
      def run() do
        Buyer1civ.get_book_title() ~> Seller1civ.(b)
        Seller1civ.get_price("book:" <> b) ~> Buyer1civ.(p)
        Buyer1civ.(:whatever) ~> Seller1civ.(wat)
        Seller1civ.order_book(b, wat)
        Buyer1civ.(p + 2)
      end
    end
  end

  defmodule MyBuyer1Civ do
    use TestChor1Civ.Chorex, :buyer1civ

    def get_book_title(), do: "Das Glasperlenspiel"
  end

  defmodule MySeller1Civ do
    use TestChor1Civ.Chorex, :seller1civ

    def get_price("book:Das Glasperlenspiel"), do: 40
    def get_price("Das Glasperlenspiel"), do: 39
    def get_price(_), do: 0
    def order_book(book_name, _), do: dbg(String.length(book_name))
  end

  test "choreography unsplat runs" do
    Chorex.start(
      TestChor1Civ.Chorex,
      %{Buyer1civ => MyBuyer1Civ, Seller1civ => MySeller1Civ},
      []
    )

    assert_receive {:chorex_return, Buyer1civ, 42}
    assert_receive {:chorex_return, Seller1civ, 19}
  end

  # #
  # # More complex choreographies
  # #

  test "project single-expr block" do
    stx = quote do
            def run() do
              Alice.(42)
            end
    end

    assert {_, _, _} = project(stx, __ENV__, Alice, empty_ctx(__ENV__))
  end

  quote do
    defchor [Buyer1, Buyer2, Seller1] do
      def run() do
        Buyer1.get_book_title() ~> Seller1.(b)
        Seller1.get_price("book:" <> b) ~> Buyer1.(p)
        Seller1.get_price("book:" <> b) ~> Buyer2.(p)
        Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

        if Buyer1.(p - contrib < get_budget()) do
          Buyer1[L] ~> Seller1
          Buyer1.get_address() ~> Seller1.(addr)
          Seller1.get_delivery_date(b, addr) ~> Buyer1.(d_date)
          Buyer1.(IO.inspect(d_date, label: "Buyer1 got date"))
          Buyer1.(d_date)
        else
          Buyer1[R] ~> Seller1
          Buyer1.(nil)
        end
      end
    end
  end
  |> Macro.expand_once(__ENV__)
  |> Macro.to_string()
  |> IO.puts()

  defmodule TestChor2 do
    defchor [Buyer1, Buyer2, Seller1] do
      def run() do
        Buyer1.get_book_title() ~> Seller1.(b)
        Seller1.get_price("book:" <> b) ~> Buyer1.(p)
        Seller1.get_price("book:" <> b) ~> Buyer2.(p)
        Buyer2.compute_contrib(p) ~> Buyer1.(contrib)

        if Buyer1.(p - contrib < get_budget()) do
          Buyer1[L] ~> Seller1
          Buyer1.get_address() ~> Seller1.(addr)
          Seller1.get_delivery_date(b, addr) ~> Buyer1.(d_date)
          Buyer1.(IO.inspect(d_date, label: "Buyer1 got date"))
          Buyer1.(d_date)
        else
          Buyer1[R] ~> Seller1
          Buyer1.(nil)
        end
      end
    end
  end

  defmodule MySeller1 do
    use TestChor2.Chorex, :seller1

    def get_delivery_date(_book, _addr) do
      IO.puts("getting delivery date for")
      ~D[2024-05-13]
    end

    def get_price("book:Das Glasperlenspiel"), do: 42
    def get_price("book:Zen and the Art of Motorcycle Maintenance"), do: 13
  end

  defmodule MyBuyer1 do
    use TestChor2.Chorex, :buyer1

    def get_book_title(), do: "Zen and the Art of Motorcycle Maintenance"
    def get_address(), do: "Maple Street"
    def get_budget(), do: 22
  end

  defmodule MyBuyer2 do
    use TestChor2.Chorex, :buyer2

    def compute_contrib(price) do
      IO.inspect(price, label: "Buyer 2 computing contribution of")
      price / 2
    end
  end

  test "3-party choreography runs" do
    Chorex.start(TestChor2.Chorex,
                 %{Seller1 => MySeller1,
                 Buyer1 => MyBuyer1,
                 Buyer2 => MyBuyer2},
    [])
    # ps1 = spawn(MySeller1, :init, [[]])
    # pb1 = spawn(MyBuyer1, :init, [[]])
    # pb2 = spawn(MyBuyer2, :init, [[]])

    # tok = UUID.uuid4()

    # config = %{
    #   Seller1 => ps1,
    #   Buyer1 => pb1,
    #   Buyer2 => pb2,
    #   :session_token => tok,
    #   :super => self()
    # }

    # send(ps1, {:chorex, tok, :meta, {:config, config}})
    # send(pb1, {:chorex, tok, :meta, {:config, config}})
    # send(pb2, {:chorex, tok, :meta, {:config, config}})

    assert_receive {:chorex_return, Buyer1, ~D[2024-05-13]}, 2_000
  end

  # test "get local functions from code walking" do
  #   stx =
  #     quote do
  #       42 < get_answer()
  #     end

  #   assert {_, [{Alice, {:get_answer, 0}}], []} =
  #            walk_local_expr(stx, __ENV__, Alice, empty_ctx())
  # end

  # test "get function from inside complex if instruction" do
  #   stx =
  #     quote do
  #       if Alice.(42 < get_answer()) do
  #         Alice[L] ~> Bob
  #         Alice.get_question() ~> Bob.(question)
  #         Bob.deep_thought(question) ~> Alice.(mice)
  #         Alice.(mice)
  #       else
  #         Alice[R] ~> Bob
  #         Alice.("How many roads must a man walk down?")
  #       end
  #     end

  #   {_code, behaviour_specs, _functions} = project(stx, __ENV__, Alice, empty_ctx())

  #   assert [{Alice, {:get_question, 0}}, {Alice, {:get_answer, 0}}] =
  #            behaviour_specs |> Enum.filter(fn {a, _} -> a == Alice end)

  #   assert [{Bob, {:deep_thought, 1}}] =
  #            behaviour_specs |> Enum.filter(fn {a, _} -> a == Bob end)
  # end

  # test "no behaviour code emitted when actor has no functions to implement" do
  #   {_result, diags} =
  #     Code.with_diagnostics(fn ->
  #       Code.compile_file("test/non_behaviour_example.ex")
  #     end)

  #   assert [] = diags
  # end

  # test "projection error when sending self a message" do
  #   stx =
  #     quote do
  #       Alice.(:whatever) ~> Alice.(whatevs)
  #     end

  #   assert_raise Chorex.ProjectionError, fn ->
  #     Chorex.project(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end
  # end

  # describe "local expression projection" do
  #   test "single variable" do
  #     stx =
  #       quote do
  #         Alice.(foo)
  #       end

  #     # Projection for Alice
  #     assert {{:foo, [], _}, [], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Projection for Bob: should be nothing (empty block)
  #     mzero = WriterMonad.mzero()
  #     assert match?(^mzero, Chorex.project_local_expr(stx, __ENV__, Bob, Chorex.empty_ctx()))
  #   end

  #   test "simple patterns" do
  #     stx1 =
  #       quote do
  #         Alice.({:ok, foo})
  #       end

  #     assert {{:ok, {:foo, [], _}}, [], []} =
  #              Chorex.project_local_expr(stx1, __ENV__, Alice, Chorex.empty_ctx())

  #     stx2 =
  #       quote do
  #         Alice.({:ok, foo, bar})
  #       end

  #     assert {{:{}, _, [:ok, {:foo, [], _}, {:bar, [], _}]}, [], []} =
  #              Chorex.project_local_expr(stx2, __ENV__, Alice, Chorex.empty_ctx())

  #     stx3 =
  #       quote do
  #         Alice.({:ok, foo, bar, baz})
  #       end

  #     assert {{:{}, _, [:ok, {:foo, [], _}, {:bar, [], _}, {:baz, [], _}]}, [], []} =
  #              Chorex.project_local_expr(stx3, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   test "expression with a variable" do
  #     stx =
  #       quote do
  #         Alice.(1 + foo)
  #       end

  #     assert {{:+, _, [1, {:foo, [], ChorexTest}]}, [], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   # Generates syntax for a function call
  #   def render_funcall({mod, ctx}, func, args) do
  #     {{:., [], [{mod, [], ctx}, func]}, [], args}
  #   end

  #   def render_var(var_name) do
  #     {var_name, [], __MODULE__}
  #   end

  #   test "expressions with function calls" do
  #     # Simple function
  #     stx =
  #       quote do
  #         Alice.(1 + foo())
  #       end

  #     foo_call = render_funcall({:impl, Chorex}, :foo, [])

  #     assert {{:+, _, [1, ^foo_call]}, [{Alice, {:foo, 0}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Simple function with arg
  #     stx =
  #       quote do
  #         Alice.(1 + foo(bar))
  #       end

  #     foo_call = render_funcall({:impl, Chorex}, :foo, [{:bar, [], ChorexTest}])

  #     assert {{:+, _, [1, ^foo_call]}, [{Alice, {:foo, 1}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Simple function with funcall for arg
  #     stx =
  #       quote do
  #         Alice.(1 + foo(bar()))
  #       end

  #     bar_call = render_funcall({:impl, Chorex}, :bar, [])
  #     foo_call = render_funcall({:impl, Chorex}, :foo, [bar_call])

  #     assert {{:+, _, [1, ^foo_call]}, [{Alice, {:foo, 1}}, {Alice, {:bar, 0}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Funcall in 1-tuple
  #     stx =
  #       quote do
  #         Alice.({bar()})
  #       end

  #     bar_call = render_funcall({:impl, Chorex}, :bar, [])

  #     assert {{:{}, [], [^bar_call]}, [{Alice, {:bar, 0}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Funcall in 2-tuple
  #     stx =
  #       quote do
  #         Alice.({:ok, bar()})
  #       end

  #     bar_call = render_funcall({:impl, Chorex}, :bar, [])

  #     assert {{:ok, ^bar_call}, [{Alice, {:bar, 0}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Funcall in 3-tuple
  #     stx =
  #       quote do
  #         Alice.({:ok, foo, bar()})
  #       end

  #     foo_var = render_var(:foo)
  #     bar_call = render_funcall({:impl, Chorex}, :bar, [])

  #     assert {{:{}, _, [:ok, ^foo_var, ^bar_call]}, [{Alice, {:bar, 0}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   def render_alias(mod) do
  #     import Utils
  #     mod = mod |> downcase_atom() |> upcase_atom()
  #     {:__aliases__, [alias: false], [mod]}
  #   end

  #   def render_alias_call(mod, func, args) do
  #     {{:., [], [render_alias(mod), func]}, [], args}
  #   end

  #   test "call to Enum or IO etc. is preserved" do
  #     stx =
  #       quote do
  #         Alice.(Enum.foo())
  #       end

  #     enum_call = render_alias_call(Enum, :foo, [])

  #     assert {^enum_call, [], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())

  #     # Complex, nested stuff
  #     stx =
  #       quote do
  #         Alice.(1 + Enum.foo(bar(42, baz)))
  #       end

  #     enum_call =
  #       render_alias_call(Enum, :foo, [
  #         render_funcall({:impl, Chorex}, :bar, [42, render_var(:baz)])
  #       ])

  #     assert {{:+, _, [1, ^enum_call]}, [{Alice, {:bar, 2}}], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   test "call to Erlang library is preserved" do
  #     stx =
  #       quote do
  #         Alice.(:crypto.generate_key(:rsa))
  #       end

  #     call =
  #       {{:., [], [:crypto, :generate_key]}, [], [:rsa]}

  #     assert {^call, [], []} = Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   test "deeply nested pattern" do
  #     stx =
  #       quote do
  #         Alice.({foo, {bar, baz, [zoop]}})
  #       end

  #     foo_var = render_var(:foo)
  #     bar_var = render_var(:bar)
  #     baz_var = render_var(:baz)
  #     zoop_var = render_var(:zoop)

  #     assert {{^foo_var, {:{}, [], [^bar_var, ^baz_var, [^zoop_var]]}}, [], []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end

  #   test "passing functions as arguments doesn't get confused" do
  #     stx =
  #       quote do
  #         Alice.(special_func(&foo/1))
  #       end

  #     # quoted form of &impl.foo/1
  #     foo_var =
  #       {:&, [],
  #        [
  #          {:/, [context: ChorexTest, imports: [{2, Kernel}]],
  #           [{{:., [], [{:impl, [], nil}, :foo]}, [no_parens: true], []}, 1]}
  #        ]}

  #     assert {{{:., [], [{:impl, [], Chorex}, :special_func]}, [], [^foo_var]},
  #             [{Alice, {:special_func, 1}}, {Alice, {:foo, 1}}],
  #             []} =
  #              Chorex.project_local_expr(stx, __ENV__, Alice, Chorex.empty_ctx())
  #   end
  # end
end

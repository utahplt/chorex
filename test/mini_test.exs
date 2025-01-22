defmodule MiniTest do
  use ExUnit.Case
  import Chorex

  # quote do
  #   defchor [Alice, Bob] do
  #     def run() do
  #       Alice.one() ~> Bob.(x)
  #       Alice.two() ~> Bob.(y)
  #       Bob.(x + y)
  #     end
  #   end
  # end
  # |> Macro.expand_once(__ENV__)
  # |> Macro.to_string()
  # |> IO.puts()

  defmodule MiniTestChor do
    defchor [Alice, Bob] do
      def run() do
        Alice.one() ~> Bob.(x)
        Alice.two() ~> Bob.(y)
        Bob.(x + y)
      end
    end
  end

  defmodule MyAlice do
    use MiniTestChor.Chorex, :alice

    @impl true
    def one(), do: 40

    @impl true
    def two(), do: 2
  end

  defmodule MyBob do
    use MiniTestChor.Chorex, :bob
  end

  test "smallest choreography test" do
    Chorex.start(MiniTestChor.Chorex, %{Alice => MyAlice, Bob => MyBob}, [])
    assert_receive({:chorex_return, Bob, 42})
  end
end

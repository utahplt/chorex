defmodule NonBehaviourExample do
  import Chorex

  defmodule TestChor do
    defchor [AliceBehaviorTest, BobBehaviorTest] do
      def run() do
        AliceBehaviorTest.hello() ~> BobBehaviorTest.(greeting)
        BobBehaviorTest.(greeting)
      end
    end
  end

  defmodule MyAliceBehaviorTest do
    use TestChor.Chorex, :alicebehaviortest

    @impl true
    def hello(), do: "world"
  end

  defmodule MyBobBehaviorTest do
    use TestChor.Chorex, :bobbehaviortest
  end
end

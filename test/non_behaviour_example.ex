defmodule NonBehaviourExample do
  import Chorex

  defmodule TestChor do
    defchor [AliceBehaviorTest, BobBehaviorTest] do
      AliceBehaviorTest.hello() ~> BobBehaviorTest.(greeting)
      BobBehaviorTest.(greeting)
    end
  end

  defmodule MyAliceBehaviorTest do
    use TestChor.Chorex, :alicebehaviortest
    def hello(), do: "world"
  end

  defmodule MyBobBehaviorTest do
    use TestChor.Chorex, :bobbehaviortest
  end
end

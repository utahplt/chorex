defmodule OooTest do
  use ExUnit.Case

  import Chorex

  defmodule OooChor do
    defchor [KeyServer, MainServer, ContentServer, Client] do
      def run() do
        ContentServer.getText() ~> MainServer.(txt)
        KeyServer.getKey() ~> MainServer.(key)
        MainServer.(txt) ~> Client.(txt)
        MainServer.(key) ~> Client.(key)
        Client.(text: txt, key: key)
      end
    end
  end

  defmodule MyKsSlow do
    use OooChor.Chorex, :keyserver
    def getKey() do
      Process.sleep(50)
      "slow-key"
    end
  end

  defmodule MyKsFast do
    use OooChor.Chorex, :keyserver
    def getKey(), do: "fast-key"
  end

  defmodule MyCsSlow do
    use OooChor.Chorex, :contentserver
    def getText() do
      Process.sleep(50)
      "slow-text"
    end
  end

  defmodule MyCsFast do
    use OooChor.Chorex, :contentserver
    def getText(), do: "fast-text"
  end

  defmodule MyMainServer do
    use OooChor.Chorex, :mainserver
  end

  defmodule MyClient do
    use OooChor.Chorex, :client
  end

  test "cs fast, ks slow" do
    Chorex.start(
      OooChor.Chorex,
      %{
        KeyServer => MyKsSlow,
        ContentServer => MyCsFast,
        MainServer => MyMainServer,
        Client => MyClient
      },
      []
    )

    assert_receive {:chorex_return, Client, [text: "fast-text", key: "slow-key"]}
  end

  test "cs slow, ks fast" do
    Chorex.start(
      OooChor.Chorex,
      %{
        KeyServer => MyKsFast,
        ContentServer => MyCsSlow,
        MainServer => MyMainServer,
        Client => MyClient
      },
      []
    )

    assert_receive {:chorex_return, Client, [text: "slow-text", key: "fast-key"]}
  end
end

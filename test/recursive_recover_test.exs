defmodule RecursiveRecoverTest do
  use ExUnit.Case
  import Chorex

  defmodule RecRecChor do
    defchor [RecRecAlice, RecRecBob] do
      def run(RecRecAlice.(times)) do
        loop(RecRecAlice.(times), RecRecBob.(1))
      end

      def loop(RecRecAlice.(i), RecRecBob.(n)) do
        try do
          if RecRecAlice.(i == 0) do
            RecRecAlice.(:done)
            RecRecBob.(n)
          else
            loop(RecRecAlice.(i - 1), RecRecBob.(n + n))
          end
        rescue
          loop(RecRecAlice.(i - 2), RecRecBob.(n + n + n))
        end
      end
    end
  end

  defmodule MyRecRecAlice do
    use RecRecChor.Chorex, :recrecalice
  end

  defmodule MyRecRecBob do
    use RecRecChor.Chorex, :recrecbob
  end

  test "small recursive choreography with try/rescue" do
    Chorex.start(RecRecChor.Chorex, %{RecRecAlice => MyRecRecAlice, RecRecBob => MyRecRecBob}, [3])
    assert_receive {:chorex_return, RecRecBob, 8}, 500
  end

  # test "small rescue-path try/rescue choreography" do
  #   Logger.configure(level: :none) # suppress crash messages
  #   Chorex.start(RecoverTestChor.Chorex, %{RecRecAlice => MyRecRecAlice, RecRecBob => MyRecRecBob}, [1])
  #   assert_receive({:chorex_return, RecRecAlice, 98}, 1_000)
  #   assert_receive({:chorex_return, RecRecBob, 99}, 1_000)
  #   Logger.configure(level: :warning) # restore
  # end


  defmodule MiniBlock do
    defchor [Searcher, Verifier] do
      def run(Verifier.(data)) do
        with Verifier.(start_nonce) <- Verifier.start_nonce() do
          Verifier.({data, start_nonce}) ~> Searcher.({data, start_nonce})
          with Verifier.({nonce, hash}) <- search(Verifier.({data, start_nonce}), Searcher.({data, start_nonce}), Searcher.(0)) do
            Verifier.({nonce, hash})
            Searcher.(:good_job)
          end
        end
      end

      def search(Verifier.({data, n}), Searcher.({data, n}), Searcher.(x)) do
        Searcher.log(data, n, x)
        Verifier.log(data, n)
        try do
          with Searcher.(hash) <- Searcher.hash(data, n + x) do
            Searcher.(hash) ~> Verifier.(hash)
            if Verifier.good_hash?(hash) do
              Searcher.(n + x) ~> Verifier.(final_nonce)
              Verifier.({final_nonce, hash})
            else
              search(Verifier.({data, n}), Searcher.({data, n}), Searcher.(x + 1))
              # with Verifier.({final_nonce, hash}) <- search(Verifier.({data, n}), Searcher.({data, n}), Searcher.(x + 1)) do
              #   Verifier.({final_nonce, hash})
              # end
            end
          end
        rescue
          search(Verifier.({data, n}), Searcher.({data, n}), Searcher.(x + 1))
        end
      end
    end
  end

  defmodule MySearcher do
	use MiniBlock.Chorex, :searcher

    @impl true
    def hash(data, nonce) do
	  :crypto.hash(:sha256, data <> <<nonce>>)
      # nonce
    end

    @impl true
    def log(_data, _n, _x) do
      # dbg({:searcher, n, x})
    end
  end

  defmodule MyVerifier do
    use MiniBlock.Chorex, :verifier

    @impl true
    def log(_data, _n) do
      # dbg({:verifier, n})
    end

    @impl true
    def good_hash?(bin) do
	  <<0>> == binary_slice(bin, 0, 1)
      # bin > 45
    end

    @impl true
    def start_nonce() do
	  0
    end
  end

  test "run buggy recursive test" do
    data = "hello"
    Chorex.start(MiniBlock.Chorex, %{Searcher => MySearcher, Verifier => MyVerifier}, [data])

    assert_receive {:chorex_return, Searcher, :good_job}
    assert_receive {:chorex_return, Verifier, {242, <<0>> <> _}}
  end
end

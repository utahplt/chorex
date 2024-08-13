defmodule GeneralizedFunctionsTest do
  use ExUnit.Case
  import Chorex

  defmodule MyCrypto do
    defchor [AliceC, BobC] do
      def run(AliceC.(msg)) do
        with BobC.({pub, priv}) <- BobC.gen_key(),
             AliceC.(whatever) <- AliceC.(40 + 2) do
          BobC.(pub) ~> AliceC.(key)
          exchange_message(AliceC.encrypt(msg <> "\n  love, Alice (" <> to_string(whatever) <> ")" , key), BobC.(priv))
        end
      end

      def exchange_message(AliceC.(enc_msg), BobC.(priv)) do
        AliceC.(enc_msg) ~> BobC.(enc_msg)
        AliceC.(:letter_sent)
        BobC.decrypt(enc_msg, priv)
      end
    end
  end

  defmodule MyAlice do
    use MyCrypto.Chorex, :alicec

    def encrypt(msg, [expt, modulus]) do
      :crypto.mod_pow(msg, expt, modulus)
    end
  end

  defmodule MyBob do
    use MyCrypto.Chorex, :bobc

    def gen_key() do
      :crypto.generate_key(:rsa, {512, 5})
    end

    def decrypt(msg, [_pub_expt, modulus, priv_expt | _]) do
      :crypto.mod_pow(msg, priv_expt, modulus)
    end
  end

  test "basic key exchange with rich functions works" do
    Chorex.start(MyCrypto.Chorex,
      %{ AliceC => MyAlice,
         BobC => MyBob },
      ["hello, world"])

    assert_receive {:chorex_return, AliceC, :letter_sent}
    assert_receive {:chorex_return, BobC, "hello, world\n  love, Alice (42)"}
  end
end

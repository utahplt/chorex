defmodule Utils do
  @doc """
  iex> Utils.upcase_atom(:foo)
  :Foo
  """
  def upcase_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.capitalize()
    |> String.to_atom()
  end

  @doc """
  iex> Utils.downcase_atom(Foo)
  :foo
  """
  def downcase_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.downcase()
    |> String.replace_prefix("elixir.", "")
    |> String.to_atom()
  end

  def fresh_atom(prefix) do
    String.to_atom(prefix <> to_string(abs(:erlang.monotonic_time())))
  end

  def assoc_put(alist, k, v), do: [{k, v} | alist]

  @doc """
  Delete first instance of key `k`.
  """
  def assoc_del([], _k), do: []
  def assoc_del([{k, _} | cdr], k), do: cdr
  def assoc_del([{l, _} = car | cdr], k) when l != k, do: [car | assoc_del(cdr, k)]
  # def assoc_del(alist, k),
  #   do:
  #     Enum.filter(alist, fn
  #       {^k, _} -> false
  #       _ -> true
  #     end)

  # Lispy: treat nil like []
  def assoc_get(nil, _), do: nil
  def assoc_get(alist, k),
    do:
      Enum.find(alist, fn
        {^k, _} -> true
        _ -> false
      end)
end

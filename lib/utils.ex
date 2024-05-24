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
end

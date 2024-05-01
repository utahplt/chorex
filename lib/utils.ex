defmodule Utils do
  @doc """
  iex>
  """
  def upcase_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.capitalize()
    |> String.to_atom()
  end

  def downcase_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.downcase()
    |> String.replace_prefix("elixir.", "")
    |> String.to_atom()
  end
end

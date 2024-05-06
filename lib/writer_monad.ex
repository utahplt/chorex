defmodule WriterMonad do
  @moduledoc """
  Makes it easy to do operations on code and track gathered data.
  """

  @type t() :: {any(), [any()]}

  @spec bind({a, b}, (a -> {c, [b]})) :: {c, [b]} when a: var, b: var, c: var
  def bind({m_d, m_l}, f) do
    {m_dd, m_ll} = f.(m_d)
    {m_dd, m_ll ++ m_l}
  end

  def m ~>> f, do: bind(m, f)

  @spec return(v :: any()) :: t()
  def return(v), do: {v, []}

  @spec mapM(vs :: [a], f :: (a -> t())) :: t() when a: var
  def mapM(vs, f) do
    results = vs |> Enum.map(f)

    {
      results
      |> Enum.map(&elem(&1, 0)),
      results
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce([], &++/2)
    }
  end

  defp transform_lines([{:<-, _, [var, expr]} | rst]) do
    quote do
      unquote(expr) ~>> fn unquote(var) -> unquote(transform_lines(rst)) end
    end
  end

  defp transform_lines([expr]), do: expr

  @doc """
  Haskell-like `do` notation for monads.

  iex> import WriterMonad
  iex> monadic do
  ...>   thing1 <- return(5)
  ...>   thing2 <- {thing1 + 2, ["foo"]}
  ...>   thing3 <- {thing1 + thing2, ["bar"]}
  ...>   return thing3
  ...> end
  {12, ["bar", "foo"]}
  """
  defmacro monadic(do: {:__block__, _, lines}) do
    transform_lines(lines)
  end
end

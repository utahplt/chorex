defmodule WriterMonad do
  @moduledoc """
  Makes it easy to do operations on code and track gathered data.
  """

  @typedoc """
  {expression, [callback_spec], [fresh_functions]}
  """
  @type t() :: {any(), [any()], [any()]}

  @spec bind({a, [b], [d]}, (a -> {c, [b], [d]})) :: {c, [b], [d]}
        when a: var, b: var, c: var, d: var
  def bind({m_d, m_l, m_f}, f) do
    {m_dd, m_ll, m_ff} = f.(m_d)
    {m_dd, m_ll ++ m_l, m_f ++ m_ff}
  end

  def m ~>> f, do: bind(m, f)

  @spec fmap({a, [b], [c]}, (a -> d)) :: {d, [b], [c]} when a: var, b: var, c: var, d: var
  def fmap({val, l1, l2}, f) do
    {f.(val), l1, l2}
  end

  def m <~> f, do: fmap(m, f)

  @spec return(v :: any()) :: t()
  def return(v), do: {v, [], []}

  @spec return(v :: any(), xs :: [any()]) :: t()
  def return(v, xs), do: {v, xs, []}

  @spec return(v :: any(), xs :: [any()], ys :: [any()]) :: t()
  def return(v, xs, ys), do: {v, xs, ys}

  @spec return_func(ys :: [any()] | any()) :: t()
  def return_func([y]), do: {{:__block__, [], []}, [], y}
  def return_func(y), do: {{:__block__, [], []}, [], [y]}

  @spec return_func(v :: any(), ys :: [any()] | any()) :: t()
  def return_func(v, y) when is_list(y), do: {v, [], y}
  def return_func(v, y), do: {v, [], [y]}

  def mzero do
    return({:__block__, [], []})
  end

  @spec mapM(vs :: [a], f :: (a -> t())) :: t() when a: var
  def mapM(vs, f) do
    results = vs |> Enum.map(f)

    {
      results
      |> Enum.map(&elem(&1, 0)),
      results
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce([], &++/2),
      results
      |> Enum.map(&elem(&1, 2))
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
  ...>   thing2 <- {thing1 + 2, ["foo"], [:zoop]}
  ...>   thing3 <- {thing1 + thing2, ["bar"], [:quux]}
  ...>   return thing3
  ...> end
  {12, ["bar", "foo"], [:zoop, :quux]}
  """
  defmacro monadic(do: {:__block__, _, lines}) do
    transform_lines(lines)
  end
end

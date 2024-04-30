defmodule LoggingMonad do
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

  @spec mapM(f :: (a -> t()), vs :: [a]) :: t() when a: var
  def mapM(f, vs) do
    results = vs |> Enum.map(f)
    {
      results
      |> Enum.map(&elem(&1, 0)),

      results
      |> Enum.map(&elem(&1, 1))
      |> Enum.reduce([], &++/2)
    }
  end
end

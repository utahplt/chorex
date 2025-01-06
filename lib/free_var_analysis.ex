defmodule FreeVarAnalysis do
  @moduledoc """
  Free variable analysis for Elixir expressions
  """

  defguard is_var(stx) when is_atom(elem(stx, 0)) and is_atom(elem(stx, 2))

  def is_var?(stx) when is_var(stx), do: true
  def is_var?(_), do: false

  def var_name({n, _, _} = stx) when is_var(stx), do: n

  @doc """
  Collect all variables mentioned in some syntax, free or otherwise.

  iex> all_vars(quote do: x)
  [:x]
  iex> all_vars(quote do: fn x -> x + 1 end)
  [:x]
  iex> all_vars(quote do: fn x -> x + y end)
  [:x, :y]
  """
  def all_vars(stx) do
    {_, acc} = Macro.prewalk(stx, [],
                             fn x, acc when is_var(x) -> {x, [var_name(x) | acc]}
                               x, acc -> {x, acc} end)
    acc |> Enum.sort() |> Enum.dedup()
  end

  def free_vars(stx, bound \\ MapSet.new())

  def free_vars(stx, bound) when is_var(stx) do
    if MapSet.member?(bound, stx), do: [], else: [stx]
  end

  def free_vars({:fn, _meta, clauses}, bound), do: free_fn_clauses(clauses, bound)

  defp free_fn_clauses(clauses, bound) do
    clauses
    |> Enum.flat_map(fn {:->, _meta, [params, body]} ->
      {free, pat_bindings} = extract_pattern_vars(params, bound)
      new_bound = Enum.reduce(pat_bindings, bound, &MapSet.put(&2, &1))
      free ++ free_vars(body, new_bound)
    end)
  end

  def extract_pattern_vars(expr, bound \\ MapSet.new()) do
    {free, bound_set} =
      Macro.prewalk(expr, {[], bound}, fn
        # Ignore _ variables
        {:_, _, _} = e, acc -> {e, acc}
        # Pinned variables: might be free
        {:^, _, [var]}, {free, bindings} when is_var(var) ->
          # nil: don't walk further into the variable
          {nil, (if bound?(var, bindings), do: {free, bindings}, else: {[var | free], bindings})}
        # Naked variables: these create new bindings
        e, {free, bindings} when is_var(e) ->
          {e, (if bound?(e, bindings), do: {free, bindings}, else: {free, MapSet.put(bindings, e)})}
        # All other things: keep walking
        e, acc -> {e, acc}
      end)
      |> elem(1)

    {free, MapSet.to_list(bound_set)}
  end

  defp bound?(var, binds), do: MapSet.member?(binds, var)
end

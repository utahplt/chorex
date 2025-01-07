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

  iex> all_vars(quote do: x) |> Enum.map(&elem(&1, 0))
  [:x]
  iex> all_vars(quote do: fn x -> x + 1 end) |> Enum.map(&elem(&1, 0))
  [:x]
  iex> all_vars(quote do: fn x -> x + y end) |> Enum.map(&elem(&1, 0))
  [:x, :y]
  """
  def all_vars(stx) do
    {_, acc} =
      Macro.prewalk(stx, MapSet.new(), fn
        x, acc when is_var(x) -> {x, extend(x, acc)}
        x, acc -> {x, acc}
      end)

    # Clobber duplicates
    acc |> MapSet.to_list()
  end

  def free_vars(stx, bound \\ MapSet.new()) do
    {_ast, {free, _all_bound}} =
      Macro.prewalk(stx, {MapSet.new(), bound}, fn
        # Assignment
        {:=, _, [bind_expr, val]}, {free, bound} ->
          {new_free, new_bound} = extract_pattern_vars(bind_expr)
          {val, {extend(new_free, free), extend(new_bound, bound)}}

        {:fn, _meta, clauses}, {free, bound} ->
          {nil, {extend(free_fn_clauses(clauses, bound), free), bound}}

        {:with, _meta, clauses}, {free, bound} ->
          {nil, {extend(free_with_clauses(clauses, bound), free), bound}}

        v, {free, bound} = acc when is_var(v) ->
          if bound?(v, bound), do: {nil, acc}, else: {nil, {extend(v, free), bound}}

        # All others: keep walking
        e, acc -> {e, acc}
      end)

    free |> MapSet.to_list()
  end

  defp free_fn_clauses(clauses, bound) do
    clauses
    |> Enum.flat_map(fn {:->, _meta, [params, body]} ->
      {free, pat_bindings} = extract_pattern_vars(params, bound)
      new_bound = extend(pat_bindings, bound)
      free ++ free_vars(body, new_bound)
    end)
  end

  defp free_with_clauses(clauses, bound) do
    clauses
    |> Enum.reduce({MapSet.new(), bound}, fn
      {:<-, _meta, [pat, expr]}, {free, bound} ->
        {pat_free, pat_intros} = extract_pattern_vars(pat, bound)
        expr_free = free_vars(expr, bound)
        {extend(pat_free, extend(expr_free, free)), extend(pat_intros, bound)}

      [do: expr], {free, bound} ->
        {extend(free_vars(expr, bound), free), bound}
    end)
    |> elem(0)
  end

  @type full_var :: {atom(), any(), atom()}
  @type ast :: any()

  @spec extract_pattern_vars(expr :: ast(), bound :: MapSet.t()) ::
          {free_vars :: [full_var()], new_bindings :: [full_var()]}
  def extract_pattern_vars(expr, bound \\ MapSet.new()) do
    {free, bound_set} =
      Macro.prewalk(expr, {[], bound}, fn
        # Ignore _ variables
        {:_, _, _} = e, acc ->
          {e, acc}

        # Pinned variables: might be free
        {:^, _, [var]}, {free, bindings} when is_var(var) ->
          # nil: don't walk further into the variable
          {nil, if(bound?(var, bindings), do: {free, bindings}, else: {[var | free], bindings})}

        # Naked variables: these create new bindings
        e, {free, bindings} when is_var(e) ->
          {e,
           if(bound?(e, bindings), do: {free, bindings}, else: {free, MapSet.put(bindings, e)})}

        # All other things: keep walking
        e, acc ->
          {e, acc}
      end)
      |> elem(1)

    {free, MapSet.to_list(bound_set)}
  end

  defp bound?(var, binds), do: MapSet.member?(binds, var)

  defp extend(%MapSet{} = vars, binds), do: MapSet.union(vars, binds)
  defp extend(vars, binds) when is_list(vars), do: Enum.reduce(vars, binds, &extend(&1, &2))
  defp extend(var, binds), do: MapSet.put(binds, var)
end

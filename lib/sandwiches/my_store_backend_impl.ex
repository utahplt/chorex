defmodule MyStoreBackendImpl do
  # import StoreBackend
  @behaviour StoreBackend

  def make_sandwich(bread, ingredients) do
    IO.inspect(bread, label: "bread")
    IO.inspect(ingredients, label: "ingredients")
    [bread] ++ ingredients ++ [bread]
  end
end

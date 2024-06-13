defmodule MyStoreBackendImpl do
  import StoreBackend
  @behaviour StoreBackend

  def make_sandwich(bread, ingredients), do: [bread] ++ ingredients ++ [bread]
end

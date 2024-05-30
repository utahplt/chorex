defmodule Chorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :chorex,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "Chorex",
      source_url: "https://github.com/utahplt/chorex"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp deps do
    []
  end

  defp description() do
    "Chorex implements choreographic programming for Elixir with macros"
  end

  defp package() do
    [
      name: "chorex",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/utahplt/chorex"}
    ]
  end
end

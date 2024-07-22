defmodule Chorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :chorex,
      version: "0.3.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "Chorex",
      source_url: "https://github.com/utahplt/chorex",
      docs: [
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description() do
    """
    Chorex enables choreographic programming for Elixir through macros.

    This is a research project intended to push on the boundaries of
    what choreographic programming can achieve through a real-world
    implementation of a choreography compiler.
    """
  end

  defp package() do
    [
      name: "chorex",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/utahplt/chorex"}
    ]
  end
end

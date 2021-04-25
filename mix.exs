defmodule Dogmatix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @name "Dogmatix"
  @source_url "https://github.com/vptheron/dogmatix"

  def project do
    [
      app: :dogmatix,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      name: @name,
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description, do: "A StatsD/DogStatsD client for Elixir"

  defp deps do
    [
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Vincent Theron"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: @name,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end

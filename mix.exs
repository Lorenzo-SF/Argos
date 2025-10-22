defmodule Argos.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos,
      version: "1.0.0",
      elixir: "~> 1.18.2-otp-27",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"],
      package: package(),
      source_url: "https://github.com/lorenzo-sf/argos",
      homepage_url: "https://hex.pm/packages/argos",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "LICENSE"],
        source_ref: "v1.0.0",
        source_url: "https://github.com/lorenzo-sf/argos"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      quality: [
        "format",
        "deps.get",
        "credo --strict --format=oneline",
        "compile --warnings-as-errors",
        "cmd 'echo \"✅ mix compile terminado\"'",
        "cmd MIX_ENV=test mix test",
        "cmd 'echo \"✅ mix test terminado\"'",
        "credo --strict",
        "cmd 'echo \"✅ mix credo terminado\"'",
        "dialyzer",
        "cmd 'echo \"✅ quality terminado\"'"
      ],
      hex_prepare: [
        "quality",
        "docs",
        "cmd mix hex.build"
      ],
      hex_publish: [
        "hex_prepare",
        "cmd mix hex.publish"
      ]
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.3", only: :dev},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false},
      {:propcheck, "~> 1.4", only: :test},
      {:credo, "~> 1.7.11", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", runtime: false},
      {:jason, "~> 1.4"}
    ]
  end

  # escript function removed - Argos is now an internal library only

  defp description do
    "Librería base para ejecución de comandos del sistema y gestión de tareas asíncronas con resultados estructurados."
  end

  defp package do
    [
      name: "argos",
      licenses: ["Apache-2.0"],
      maintainers: ["Lorenzo Sánchez Fraile"],
      links: %{
        "GitHub" => "https://github.com/lorenzo-sf/argos",
        "Docs" => "https://hexdocs.pm/argos"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .dialyzer_ignore.exs)
    ]
  end
end

defmodule FlagdProvider.MixProject do
  use Mix.Project

  @git_repo "https://github.com/olunusib/openfeature-flagd-provider"

  @version "0.1.0"

  def project do
    [
      app: :open_feature_flagd_provider,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],

      # Docs
      name: "FlagdProvider",
      source_url: @git_repo,
      homepage_url: "https://hexdocs.pm/open_feature_flagd_provider",
      docs: docs(),

      # Hex
      description: "An OpenFeature provider for flagd",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.37", only: :docs, runtime: false},
      {:grpc, "~> 0.9.0"},
      {:open_feature, "~> 0.1"},
      {:mimic, "~> 1.11", only: :test},
      {:req, "~> 0.5"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp package do
    [
      maintainers: ["Best Olunusi"],
      links: %{
        "GitHub" => @git_repo,
        "Changelog" => "https://hexdocs.pm/open_feature_flagd_provider/changelog.html"
      }
    ]
  end
end

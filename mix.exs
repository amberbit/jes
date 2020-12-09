defmodule Jes.MixProject do
  use Mix.Project

  def project do
    [
      app: :jes,
      description: "Jes stands for JSON Events Stream. It's a JSON parser which outputs Stream of events.",
      version: "0.1.2",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end


  def package do
    [
      maintainers: ["Hubert Łępicki"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/amberbit/jes"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end

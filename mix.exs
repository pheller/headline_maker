defmodule HeadlineMaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :headline_maker,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: HeadlineMaker]
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
      {:req, "~> 0.5"},
      {:httpoison, "~> 1.8.2"},
      {:quinn, "~> 1.1.3"},
      {:floki, "~> 0.36"},
      # StandardMenu (the XXOPSM00 call that makes a page's numbered fields
      # navigate) and NaplpsText (proportional metrics, hyphenation, line
      # breaking) are both upstream now, so these are plain upstream deps.
      # naplps_writer needs no override: prodigy_objects names the same source.
      {:prodigy_objects, git: "https://github.com/rrcook/prodigy_objects.git"},
      {:naplps_writer, git: "https://github.com/rrcook/naplps_writer.git"}
    ]
  end
end

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
      # INTERIM: our fork carries StandardMenu, which encodes the XXOPSM00 call
      # that makes a page's numbered fields navigate. Repoint to
      # rrcook/prodigy_objects once that is upstreamed.
      {:prodigy_objects,
       git: "https://github.com/pheller/prodigy_objects.git", branch: "standard-menu"},
      # INTERIM: our fork carries NaplpsText (proportional metrics, hyphenation,
      # line breaking) which the pre-wrapping work needs. Repoint to
      # rrcook/naplps_writer once that is upstreamed.
      #
      # override: prodigy_objects depends on naplps_writer from rrcook's URL,
      # and mix refuses two sources for one dep without being told which wins.
      {:naplps_writer,
       git: "https://github.com/pheller/naplps_writer.git", branch: "text-metrics", override: true}
    ]
  end
end

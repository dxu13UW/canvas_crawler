# mix.exs
defmodule CanvasCrawler.MixProject do
  use Mix.Project

  def project do
    [
      app: :canvas_crawler,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [test: "test --no-start"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key],
      mod: {CanvasCrawler.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:gen_smtp, "~> 1.2"},
      {:tz, "~> 0.28"}
    ]
  end
end

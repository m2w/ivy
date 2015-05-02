defmodule Ivy.Main.Mixfile do
  use Mix.Project

  def project do
    [app: :ivy,
     version: "0.0.1",
     elixir: "~> 1.0",
     source_url: "https://github.com/m2w/ivy",
     homepage: "https://m2w.github.com/ivy",
     escript: [main_module: Ivy.Core,
               emu_args: "-setcookie weCanBlogForDays!"],
     deps: deps]
  end

  def application do
    [applications: [:logger,
                    :mix,
                    :eex,
                    :cowboy,
                    :plug]]
  end

  defp deps do
    [{:earmark, "~> 0.1.15"},
     {:cowboy, "~> 1.0.0"},
     {:plug, "~> 0.12.1"},
     {:cowlib, "1.0.1"},
     {:ranch, "~> 1.0.0"},
     {:exprof, "~> 0.2.0", only: :dev},
     {:file_monitor, github: "richcarl/file_monitor", ref: "master"},
     {:ex_doc, "~> 0.7.2", only: :dev}]
  end
end

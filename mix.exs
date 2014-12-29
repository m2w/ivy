defmodule Ivy.Main.Mixfile do
  use Mix.Project

  def project do
    [app: :ivy,
     version: "0.0.1",
     elixir: "~> 1.0",
     escript: [main_module: Ivy.Core,
               emu_args: "-setcookie weCanBlogForDays!"],
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger,
                    :mix,
                    :eex,
                    :cowboy,
                    :plug]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [{:earmark, "~> 0.1.12"},
     {:cowboy, "~> 1.0.0"},
     {:plug, "~> 0.9.0"},
     {:cowlib, "1.0.0"},
     {:ranch, "~> 1.0.0"}]
  end
end

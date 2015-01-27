defmodule Ivy.Skeleton do
  @moduledoc """
Contains functionality and templates to generate a basic skeleton for an ivy site.
"""

  @gitignore """
_out/
"""

  # FIXME: transition to run-time definition and use plain string substitution instead?
  @ivy_conf """
use Mix.Config

# Add/modify ivy behaviour below:
config :ivy,
  # directory structure, paths *must be* relative to the root dir
  posts: "_posts",
  out: "_out",
  templates: "_templates",
  includes: "_includes",
  pages: "_pages",
  static: "static",
  title: "TITLE_PLACEHOLDER",
  author: "AUTHOR_PLACEHOLDER"
  # any other keyword defined here is available in all templates,
  # these keywords can however be overwritten through in markdown meta-data
"""

  @readme """
# Welcome to ivy!

ivy is a static site generator. To get started, simply run `ivy -s`
and then visit [localhost:4000](http://localhost:4000).
"""

  @doc "Generate a skeleton for an ivy."
  @spec create(String.t) :: no_return
  def create(name) do
    cwd = File.cwd!
    if Path.type(name) == :relative do
      p = Path.expand(Path.join(cwd, name))
    else
      p = name
    end
    if File.exists?(name) do
      IO.puts "#{name} already exists, aborting."
      System.halt(126)
    end
    n = Path.basename(name)
    pn = IO.gets("Provide a title for your site [#{n}]: ")
    if String.length(String.strip(pn)) > 0 do
      n = pn
    end
    a = System.get_env("USER")
    pa = IO.gets("What is your name [#{a}]?")
    if String.length(String.strip(pa)) > 0 do
      a = pa
    end

    conf = String.replace(@ivy_conf, "AUTHOR_PLACEHOLDER", a)
    conf = String.replace(conf, "TITLE_PLACEHOLDER", n)

    # create the root dir
    File.mkdir!(name)
    # write README
    File.write!(Path.join(p, "README"), @readme)
    # write .gitignore
    File.write!(Path.join(p, ".gitignore"), @gitignore)
    # write ivy_conf.exs
    File.write!(Path.join(p, "ivy_conf.exs"), conf)
    # create the default directory structure
    Enum.each(["_out", "_posts", "_templates", "_includes", "_pages", "static"],
             &(File.mkdir!(Path.join(name, &1))))

    # TODO: add default styling and a landing page

    IO.puts "Your ivy has been planted!"
    System.halt(0)
  end
end

defmodule Post do
  defstruct contents: "", meta: [], uri: ""
end

defmodule Page do
  defstruct html: "", meta: [], uri: ""
end

defmodule Template do
  defstruct tpl: "", meta: [], name: ""
end

defmodule Ivy.Utils do
  @doc """
Parse a the beginning of a document, extracting any md-style meta-data.

Meta-data is returned as a Keyword.
"""
  def extract_meta(f_stream, :init) do
    if String.starts_with? hd(Enum.take(f_stream, 1)), "---" do
       extract_meta(f_stream, :run)
    else
      []
    end
  end
  def extract_meta(f_stream, :run) do
    f_stream
    |> Stream.drop(1)
    |> Enum.take_while(&(! String.starts_with? &1, "---"))
    |> Enum.map(fn l -> Keyword.new([String.split(l, ":", trim: true)],
                                        fn [x,y] ->
                                          {atomify(x),
                                           String.strip(y)}
                                        end)
                end)
    |> List.flatten
  end

  @doc "Strip, lowercase and `to_atom` a String."
  def atomify(s) do
    String.to_atom(String.downcase(String.strip(s)))
  end
end

defmodule Ivy.Core do
  @version Keyword.get(Mix.Project.config(), :version)
  # TODO
  # "watch" functionality
  # "plugin" framework
  # tests
  # error handling
  # pagination

  @doc "Runs a local server."
  def run_server(port) do
    {:ok, _} = Plug.Adapters.Cowboy.http LocalServer, [], port: port
    IO.puts "Ivy growing on port #{port}"

    :timer.sleep(:infinity)
  end

  @doc "Entry point for the escript."
  def main(args) do
    if length(args) > 0 do
      {parsed, _argv, _errs} = OptionParser.parse(args,
                                                  switches: [port: :integer,
                                                             serve: :boolean,
                                                             new: :string],
                                                  aliases: [p: :port, v: :version,
                                                            w: :watch, s: :serve,
                                                            n: :new])

      # TODO: refactor?
      serve = Keyword.get(parsed, :serve, false)
      port = Keyword.get(parsed, :port, 4000)
      watch = Keyword.get(parsed, :watch, false)
      version = Keyword.get(parsed, :version, false)

      if Keyword.has_key?(parsed, :new) do
        new = String.strip(Keyword.get(parsed, :new, ""))
        if String.length(new) > 0 do
          Ivy.Skel.create(new)
        else
          IO.puts "Please provide a path for the ivy skeleton."
          System.halt(126)
        end
      end

      setup()

      if serve do
        run_server(port)
      else
        if watch do
          # TODO: implement
          IO.puts "not yet implemented"
        else
          if version do
            print_version()
          else
            show_help()
          end
        end
      end
    else
      setup()
      build()
    end
  end

  @doc "Starts all Stores and configures ivy."
  def setup() do
    ConfigAgent.start_link()
    SiteStore.start_link()
    TemplateStore.start_link()
    configure()
  end

  @doc "Print a help text."
  def show_help() do
    IO.puts """
ivy #{@version} -- ivy is a static site generator written in Elixir

Usage:
  ivy [-s | --serve] [-v | --version] [-w | --watch] [-p | --port <port>]
      [-n | --new <path>]

Description:
TODO
When run without options, ivy will simply build your site.

Options:
  -h, --help
    Display this help text
  -n, --new
    Generate a skeleton ivy
  -s, --serve
    Locally serve your site
  -v, --version
    Display the version number
  -w, --watch
    Watch for changes and automatically rebuild your site

"""
  end

  @doc "Print the name and version number."
  def print_version() do
    IO.puts "ivy #{@version}"
  end

  @doc "Parses and activates the local config."
  def configure() do
    cwd = File.cwd!
    config_file = Path.absname("ivy_conf.exs", cwd)
    if File.exists?(config_file) do
      [{:ivy, config}] = Mix.Config.read!(config_file)
      ConfigAgent.set_config(config)
    end

    ConfigAgent.prepend_path([:out, :posts, :templates, :includes, :static], cwd)
  end

  @doc "Parse templates, pages and posts and render them to file."
  def build() do
    start = :erlang.now()
    IO.puts "Your ivy is now growing!"

    clean_out_dir()
    copy_static_files()

    # parse local config (provide defaults)
    out_dir = ConfigAgent.get(:out)
    if !(File.dir?(out_dir)) do
      IO.puts "Ivy needs #{out_dir} to exist and be a directory"
      System.halt(126)
    end

    # grab posts
    md_posts = Mix.Utils.extract_files([ConfigAgent.get(:posts)], "*.md")
    md_posts = Enum.filter(md_posts, &String.match?(&1, ~r/\d{4}-\d{1,2}-\d{1,2}-.+/))

    # grab pages
    md_pages = Mix.Utils.extract_files([ConfigAgent.get(:pages)], "*.md")
    raw_pages = Mix.Utils.extract_files([ConfigAgent.get(:pages)], "*.html")

    # raws simply get copied
    copy_raw(raw_pages)

    # grab includes
    prep_includes()

    # templating
    templates = Mix.Utils.extract_files([ConfigAgent.get(:templates)], "*.html")
    Enum.map(templates, &TemplateStore.prep_template/1)
    TemplateStore.handle_template_hierarchy()
    TemplateStore.compile_templates()

    # render posts and pages
    Enum.map(md_posts, &render(&1, :post))
    Enum.map(md_pages, &render(&1, :page))

    # add index
    build_index()

    elapsed = :timer.now_diff(:erlang.now(), start)
    IO.puts("Ivy finished growing after #{elapsed / 1000000} seconds")
  end

  @doc "Copies files to the `:out` dir."
  def copy_raw([]) do
    []
  end
  def copy_raw([f|rem_f]) do
    File.cp!(f, ConfigAgent.get(:out))
    copy_raw(rem_f)
  end

  @doc "Removes any stale artefacts from previous runs before building."
  def clean_out_dir() do
    out = ConfigAgent.get(:out)
    File.rm_rf!(out)
    File.mkdir!(out)
  end

  @doc "Copies the static dir into `:out`"
  def copy_static_files() do
    out = ConfigAgent.get(:out)
    static = ConfigAgent.get(:static)
    if File.dir? static do
      p = Path.join(out, Path.basename(static))
      File.mkdir!(p)
      File.cp_r!(static, p)
    end
  end

  @doc "Renders an index.html"
  def build_index() do
    fname = "index.html"

    if File.exists? fname do
      posts = SiteStore.get_all_posts()
      pages = SiteStore.get_all_pages()

      meta = Ivy.Utils.extract_meta(File.stream!(fname), :init)
      meta = ConfigAgent.local_conf(meta)
      t = TemplateStore.get(Keyword.get(meta, :layout, "base"))

      {out, _ctx} = Code.eval_quoted(t.tpl,
                                     [assigns: Keyword.merge(meta,
                                                             [posts: posts,
                                                              pages: pages])])

      fname = "index.html"
      out_path = Path.join(ConfigAgent.get(:out), fname)
      File.write!(out_path, out)
    else
      IO.puts "Ivy could not locate an 'index.html' template => not generating an index."
    end
  end

  defp prep_includes() do
    incl = ConfigAgent.get(:includes)
    if File.dir? incl do
      incls = Mix.Utils.extract_files([incl], "*.html")
      Enum.each(incls, fn inc ->
                  name = "include/" <> Path.basename(inc)
                  contents = File.read! inc
                  TemplateStore.put(name, %Template{tpl: contents, name: name})
                  end)
    end
  end

  defp parse_md(f) do
    meta = Ivy.Utils.extract_meta(File.stream!(f), :init)
    meta = ConfigAgent.local_conf(meta)
    lines = case length(meta) do
             x when x > 0 -> x + 2
             _ -> 1
            end
    html = File.stream!(f)
    |> Stream.drop(lines)
    |> Enum.to_list
    |> Earmark.to_html

    {html, meta}
  end

  defp write_html(f, {html, meta}) do
    t = TemplateStore.get(Keyword.get(meta, :layout, "base"))
    data = Keyword.merge(meta, [content: html])

    {html, _ctx} = Code.eval_quoted(t.tpl, [assigns: data], __ENV__)

    fname = Path.basename(f, ".md") <> ".html"
    out_path = Path.join(ConfigAgent.get(:out), fname)

    File.write!(out_path, html)

    {fname, html}
  end

  defp render(f, :post) do
    {html, meta} = parse_md(f)
    datep = String.split(f, "-", parts: 4)
    # TODO: do we want to enforce the same filename structure as jekyll?

    date = datep
    |> Enum.take(3)
    |> String.to_integer
    |> List.to_tuple

    {_, time} = File.stat!(f).mtime

    meta = Keyword.merge(meta, [date: {date, time}])

    {fname, _} = write_html(f, {html, meta})

    SiteStore.set(%Post{uri: fname, contents: html, meta: meta})
  end
  defp render(f, :page) do
    {html, meta} = parse_md(f)

    {fname, raw} = write_html(f, {html, meta})

    SiteStore.set(%Page{uri: "page/" <> fname, html: raw, meta: meta})
  end
end

defmodule SiteStore do
  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  def set(%Post{uri: uri} = post) do
    Agent.update(__MODULE__, &Dict.put(&1, uri, post))
  end
  def set(%Page{uri: uri} = page) do
    Agent.update(__MODULE__, &Dict.put(&1, uri, page))
  end

  def get(uri) do
    Agent.get(__MODULE__, &Dict.get(&1, uri))
  end

  def get_all_pages() do
    Enum.filter(get_all_content(), fn c -> c.__struct__ == Page end)
  end

  def get_all_posts() do
    Enum.filter(get_all_content(), fn c -> c.__struct__ == Post end)
  end

  def get_all_content() do
    Agent.get(__MODULE__, fn state -> state end)
  end
end


defmodule ConfigAgent do
  @default_config %{out: "_out",
                    posts: "_posts",
                    pages: "_pages",
                    templates: "_templates",
                    includes: "_includes",
                    static: "static"}

  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  def set(k, v) do
    Agent.update(__MODULE__, &Dict.put(&1, k, v))
  end

  def get(k, default \\ nil) do
    Agent.get(__MODULE__, &Dict.get(&1, k, default))
  end

  def local_conf(local_meta) do
    Keyword.merge(Agent.get(__MODULE__, fn c -> Dict.to_list(c) end), local_meta)
  end

  @doc "Prepends `path` to each `key` in `keys`"
  def prepend_path(keys, path) do
    Enum.each(keys,
              &(Agent.get_and_update(__MODULE__,
                    fn state ->
                      v = Dict.get(state, &1, "")
                      nv = Path.join(path, v)
                      {nv,  Dict.update(state, &1, v, fn _ -> nv end)}
                    end)
              )
    )
  end

  @doc "Merges the default config and `config`."
  def set_config(config) do
    conf = Dict.merge(@default_config, config)
    Enum.map(conf, fn {k, v} -> set(k, v) end)
  end
end

defmodule LocalServer do
  use Plug.Builder

  # FIXME: how can I make `from` dynamic???
  plug Plug.Static, at: "/", from: "./_out"
  plug :not_found

  def init(options) do
    options
  end

  def not_found(conn, _) do
    not_found = SiteStore.get("page/404")
    if not_found do
      Plug.Conn.send_resp(conn, 404, not_found.html)
    else
      Plug.Conn.send_resp(conn, 404, "not found")
    end
  end
end

defmodule Ivy.Skel do
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
    conf = String.replace(@ivy_conf, "TITLE_PLACEHOLDER", n)

    # create the root dir
    File.mkdir!(name)
    # write README
    File.write!(Path.join(p, "README"), @readme)
    # write .gitignore
    File.write!(Path.join(p, ".gitignore"), @gitignore)
    # write ivy_conf.exs
    File.write!(Path.join(p, "ivy_conf.exs"), conf)
    # create the default directory structure
    Enum.map(["_out", "_posts", "_templates", "_includes", "_pages", "static"],
             &(File.mkdir!(Path.join(name, &1))))

    # TODO: add default styling and a landing page

    IO.puts "Your ivy has been planted!"
    System.halt(0)
  end
end

defmodule TemplateStore do
  @content_regex ~r/<%=\s+@content\s+%>/

  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  def put(k, v) do
    Agent.update(__MODULE__, &Dict.put(&1, k, v))
  end

  def get(k) do
    Agent.get(__MODULE__, &Dict.get(&1, k))
  end

  @doc """
Recursively updates all template by traveling along their template hierarchie.

Run *after* you have `prep_template`ed all templates.
"""
  def handle_template_hierarchy() do
    templates = Agent.get(__MODULE__, &(HashDict.values(&1)))
    Enum.each(templates, &handle_template_hierarchy/1)
  end

  @doc """
Compiles all existing template strings for efficiency.

CARE: not idempotent!
"""
  def compile_templates() do
    templates = Agent.get(__MODULE__, &(HashDict.values(&1)))
    Enum.each(templates, fn t ->
                compiled = EEx.compile_string(t.tpl)
                put(t.name, %{t | tpl: compiled})
              end)
  end

  # TODO: this breaks elixir mode...
  @incl_regex ~r/<%=\s+@include\s+"([^"]+)"\s+%>/

  @doc """
Parses a template and add it to the `TemplateStore`.
"""
  def prep_template(t) do
    # TODO: use .html.eex?
    name = Path.basename(t, ".html")
    meta = Ivy.Utils.extract_meta(File.stream!(t), :init)
    lines = case length(meta) do
             x when x > 0 -> x + 2
             _ -> 1
           end

    # read the file (after meta) to string
    raw = File.open!(t, [:read], fn f ->
                      Enum.each(1..lines, fn _ -> IO.read(f, :line) end)
                      IO.read(f, :all)
                    end)

    # replace includes with the include contents
    template = Regex.replace(@incl_regex, raw,
      fn _, m ->
        t = TemplateStore.get("include/" <> m)
        if t do
          t.tpl
        else
          ""
        end
      end)

    TemplateStore.put(name, %Template{tpl: template, meta: meta, name: name})
  end

  defp handle_template_hierarchy(t) do
    pt = parent_template(t)
    if pt do
      # place child temp into content of parent temp
      template = Regex.replace(@content_regex, pt.tpl, t.tpl)

      t = %{t | tpl: template}
      pl = Keyword.get(pt.meta, :layout)
      if pl do
        meta = Keyword.update!(t.meta, :layout, pl)
        t = %{t | meta: meta}
      else
        meta = Keyword.drop(t.meta, [:layout])
        t = %{t | meta: meta}
      end
      TemplateStore.put(t.name, t)
      handle_template_hierarchy(t)
    end
  end

  defp parent_template(template) do
    pt = Keyword.get(template.meta, :layout, false)
    if pt do
      TemplateStore.get(pt)
    else
      false
    end
  end
end

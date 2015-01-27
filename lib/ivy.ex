defmodule Ivy.Types do
  @moduledoc """
Contains abstract type definitions.
"""

  @type markdown :: String.t
  @type html :: String.t
  @type meta :: Keyword.t
  @type nillable_int :: Integer.t | nil
end

# TODO: make these types more specific
defmodule Post do
  @moduledoc """
Posts represent markdown documents that form the main content of an ivy site.

They are composed of meta data, the content itself and a URI.
"""

  defstruct contents: "", meta: [], uri: ""
  @type t :: %Post{contents: String.t, meta: Ivy.Types.meta, uri: String.t}
end

defmodule Page do
  @moduledoc """
A Page refers a single page on an ivy site. They differ from posts only
in their URLs.
"""

  defstruct html: "", meta: [], uri: ""
  @type t :: %Page{html: Ivy.Types.html, meta: Ivy.Types.meta, uri: String.t}
end

defmodule Template do
  @moduledoc """
Templates are parsed markdown documents.

They can handle @include directives to include shared snippets and
implement a simple form of inheritance.
"""

  defstruct tpl: "", meta: [], name: ""
  @type t :: %Template{tpl: String.t, meta: Ivy.Types.meta, name: String.t}
end

defmodule Paginator do
  @moduledoc """
A wrapper for paginated items.

Contains links to itself, previous and following items.
"""

  defstruct prev: nil, cur: nil, next: nil, per_page: 5, items: []
  @type t :: %Paginator{prev: Ivy.Types.nillable_int, cur: non_neg_integer,
                        next: Ivy.Types.nillable_int, per_page: pos_integer,
                        items: [Post.t]}
end

defmodule Ivy.Utils do
  @moduledoc """
Contains simple helper and utility functions.
"""

  @doc """
Parse a the beginning of a document, extracting any md-style meta-data.

Meta-data is returned as a Keyword.
"""
  @spec extract_meta(File.Stream.t, :init | :run) :: Ivy.Types.meta
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
  @spec atomify(String.t) :: atom
  def atomify(s) do
    String.to_atom(String.downcase(String.strip(s)))
  end
end

defmodule Ivy.Core do
  @moduledoc """
`Ivy.Core` contains the majority of ivy's logic and its `main/1`.
"""

  @version Keyword.get(Mix.Project.config(), :version)
  # TODO
  # "watch" functionality
  # "plugin" framework
  # tests
  # error handling

  @doc "Runs a local server."
  @spec run_server(pos_integer) :: :ok
  def run_server(port) do
    {:ok, _} = Plug.Adapters.Cowboy.http LocalServer, [], port: port
    IO.puts "Ivy growing on port #{port}"

    :timer.sleep(:infinity)
  end

  @doc "Entry point for the escript."
  @spec main([any]) :: no_return
  def main(args) do
    System.at_exit(&Ivy.Core.when_done/1)

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
          GenServer.start_link(Watcher, [])
          :timer.sleep(:infinity)
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
  @spec setup() :: :ok
  def setup() do
    {:ok, _pid} = ConfigAgent.start_link()
    {:ok, _pid} = SiteStore.start_link()
    {:ok, _pid} = TemplateStore.start_link()
    configure()
  end

  @doc "Print a help text."
  @spec show_help() :: :ok
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
  @spec print_version() :: :ok
  def print_version() do
    IO.puts "ivy #{@version}"
  end

  @doc "Parses and activates the local config."
  @spec configure() :: :ok
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
  @spec build() :: :ok | no_return
  def build() do
    start = :erlang.now()
    IO.puts "Your ivy is now growing!"

    :ok = clean_out_dir()
    _paths = copy_static_files()

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
    Enum.each(templates, &TemplateStore.prep_template/1)
    TemplateStore.handle_template_hierarchy!()
    TemplateStore.compile_templates!()

    # TODO: hook in plugin modules here
    # plugin modules must expose a handle_content/0 function
    # plugins can access site data through the named agents and do their thing before ivy continiues


    # render posts and pages
    Enum.each(md_posts, &render(&1, :post))
    Enum.each(md_pages, &render(&1, :page))

    # add index
    build_index()

    elapsed = :timer.now_diff(:erlang.now(), start)
    IO.puts("Ivy finished growing after #{elapsed / 1000000} seconds")
  end

  @doc "Ensures that ivy terminates as expected even when plugins unexpectedly terminate processing."
  @spec when_done(non_neg_integer) :: :ok | no_return
  def when_done(status_code) when status_code == 0 do
    IO.puts("Ivy stopped growing.")
  end
  def when_done(_) do
  end

  @doc "Copies files to the `:out` dir."
  @spec copy_raw([Path.t]) :: :ok
  def copy_raw([]) do
    :ok
  end
  def copy_raw([f|rem_f]) do
    File.cp!(f, ConfigAgent.get(:out))
    copy_raw(rem_f)
  end

  @doc "Removes any stale artefacts from previous runs before building."
  @spec clean_out_dir() :: :ok | no_return
  def clean_out_dir() do
    out = ConfigAgent.get(:out)
    _paths = File.rm_rf!(out)
    File.mkdir!(out)
  end

  @doc "Copies the static dir into `:out`"
  @spec copy_static_files() :: no_return | [Path.t]
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
  @spec build_index() :: :ok
  def build_index() do
    fname = "index.html"

    if File.exists? fname do
      posts = SiteStore.get_all_posts()

      pages = SiteStore.get_all_pages()

      meta = Ivy.Utils.extract_meta(File.stream!(fname), :init)
      meta = ConfigAgent.local_conf(meta)
      t = TemplateStore.get(Keyword.get(meta, :layout, "base"))

      if ConfigAgent.get(:paginate, false) do
        fname = "index.html"
        fpath = Path.join(ConfigAgent.get(:out), fname)
        write_index(fpath, t, Keyword.merge(meta, [posts: posts, pages: pages]))
      else
        per_page = ConfigAgent.get(:paginate_by, 5)
        paginators = paginate_posts([%Paginator{prev: nil, cur: 0, next: 1, per_page: per_page}], posts)
        write_paginated_index(t, paginators, meta, pages)
      end
    else
      IO.puts "Ivy could not locate an 'index.html' template => not generating an index."
    end
  end

  @doc "Renders a page or post to disk."
  @spec render(Path.t, :post | :page) :: :ok
  def render(f, :post) do
    {html, meta} = parse_md(f)
    datep = String.split(Path.basename(f), "-", parts: 4)

    date = datep
    |> Enum.take(3)
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple

    stat = File.stat!(f)
    {_, time} = stat.mtime

    meta = Keyword.merge(meta, [date: {date, time}])

    {fname, _} = write_html(f, {html, meta})

    SiteStore.set(%Post{uri: fname, contents: html, meta: meta})
  end
  def render(f, :page) do
    {html, meta} = parse_md(f)

    {fname, raw} = write_html(f, {html, meta})

    SiteStore.set(%Page{uri: "page/" <> fname, html: raw, meta: meta})
  end

  # TODO: need to make next, cur and prev available as URLs not ints
  @spec write_paginated_index(Template.t, [Paginator.t],
                              Ivy.Types.meta, [Page.t]) :: :ok
  defp write_paginated_index(_, [], _, _) do
    IO.puts "Created paginated index"
  end
  defp write_paginated_index(template, [%Paginator{prev: nil} = paginator|rem], meta, pages) do
    fname = "index.html"
    fpath = Path.join(ConfigAgent.get(:out), fname)
    write_index(fpath, template, Keyword.merge(meta, [pages: pages, paginator: paginator]))
    write_paginated_index(template, rem, meta, pages)
  end
  defp write_paginated_index(template, [%Paginator{cur: cur} = paginator|rem], meta, pages) do
    dir = Path.join(ConfigAgent.get(:out), "page-"<> Integer.to_string(cur))
    if !File.dir?(dir) do
      File.mkdir!(dir)
    end
    fpath = Path.join(dir, "index.html")
    write_index(fpath, template, Keyword.merge(meta, [pages: pages, paginator: paginator]))
    write_paginated_index(template, rem, meta, pages)
  end

  @spec write_index(Path.t, Template.t, Keyword.t) :: :ok
  defp write_index(fpath, template, assigns) do
    {out, _ctx} = Code.eval_quoted(template.tpl,
                                   [assigns: assigns])
    File.write!(fpath, out)
  end

  # TODO: fix next on the last page, should be nil
  @spec paginate_posts([Paginator.t], [Post.t]) :: [Paginator.t]
  defp paginate_posts(paginators, []) do
    paginators
  end
  defp paginate_posts([%Paginator{cur: cur, next: next, per_page: per_page}|_] = paginators, posts) do
    {pp, rem} = Enum.split(posts, per_page)

    npaginator = %Paginator{prev: cur, cur: next, next: next + 1, items: pp}

    paginate_posts([npaginator|paginators], rem)
  end

  @spec prep_includes() :: Path.t | :ok
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

  @spec parse_md(Path.t) :: {Ivy.Types.html, Ivy.Types.meta}
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

  @spec write_html(Path.t,
                   {Ivy.Types.html, Ivy.Types.meta}) :: {Path.t, Ivy.Types.html}
  defp write_html(f, {html, meta}) do
    t = TemplateStore.get(Keyword.get(meta, :layout, "base"))
    data = Keyword.merge(meta, [content: html])

    {html, _ctx} = Code.eval_quoted(t.tpl, [assigns: data], __ENV__)

    fname = Path.basename(f, ".md") <> ".html"
    out_path = Path.join(ConfigAgent.get(:out), fname)

    File.write!(out_path, html)

    {fname, html}
  end
end

defmodule SiteStore do
  @moduledoc """
SiteStore is essentially a cache, that holds all (rendered) posts and pages
in memory. This cache takes the form of a `HashDict.t`.
"""

  @doc "Starts and links the `SiteStore` agent"
  @spec start_link() :: Agent.on_start
  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  @doc "Create/update a `SiteStore` entry."
  @spec set(Post.t | Page.t) :: :ok
  def set(%Post{uri: uri} = post) do
    Agent.update(__MODULE__, &Dict.put(&1, uri, post))
  end
  def set(%Page{uri: uri} = page) do
    Agent.update(__MODULE__, &Dict.put(&1, uri, page))
  end

  @doc "Returns a specific entry from the `SiteStore`."
  @spec get(String.t) :: Post.t | Page.t | nil
  def get(uri) do
    Agent.get(__MODULE__, &Dict.get(&1, uri))
  end

  @doc "Returns a list of all pages."
  @spec get_all_pages() :: [Page.t]
  def get_all_pages() do
    Enum.filter(get_all_content(), fn c -> c.__struct__ == Page end)
  end

  @doc "Returns a list of all posts."
  @spec get_all_posts() :: [Post.t]
  def get_all_posts() do
    Enum.filter(get_all_content(), fn c -> c.__struct__ == Post end)
  end

  @spec get_all_content() :: HashDict.t
  defp get_all_content() do
    Agent.get(__MODULE__, fn state -> state end)
  end
end


defmodule ConfigAgent do
  @moduledoc """
The `ConfigAgent` stores all site-wide configuration and meta-data for easy retrieval.
"""

  @default_config %{out: "_out",
                    posts: "_posts",
                    pages: "_pages",
                    templates: "_templates",
                    includes: "_includes",
                    static: "static"}

  @doc "Starts and links to the `ConfigAgent`."
  @spec start_link() :: Agent.on_start
  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  @doc "Sets a config entry."
  @spec set(atom, String.t | non_neg_integer | boolean) :: :ok
  def set(k, v) do
    Agent.update(__MODULE__, &Dict.put(&1, k, v))
  end

  @doc "Returns the entry associated with a key."
  @spec get(atom, String.t | non_neg_integer | boolean | nil) :: String.t | non_neg_integer | boolean | nil
  def get(k, default \\ nil) do
    Agent.get(__MODULE__, &Dict.get(&1, k, default))
  end

  @doc """
Returns a `Keyword.t` that merges in the global configuration.

Local configuration overwrites existing keys from the global configuration.
"""
  @spec local_conf(Keyword.t) :: Keyword.t
  def local_conf(local_meta) do
    Keyword.merge(Agent.get(__MODULE__, fn c -> Dict.to_list(c) end), local_meta)
  end

  @doc "Prepends `path` to each `key` in `keys`"
  @spec prepend_path([atom], Path.t) :: :ok
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
  @spec set_config(Keyword.t) :: :ok
  def set_config(config) do
    conf = Dict.merge(@default_config, config)
    Enum.each(conf, fn {k, v} -> set(k, v) end)
  end
end

defmodule LocalServer do
  @docmodule """
`LocalServer` is a simple plug based server to view your site locally.

It is soley intended for development.
"""

  use Plug.ErrorHandler

  def init(options) do
    options
  end

  def call(conn, _opts) do
    opts = Plug.Static.init([gzip: true, at: "/", from: ConfigAgent.get(:out)])
    nc = Plug.Static.call(conn, opts)
    if ! nc.halted do
      handle_not_found(conn, opts)
    else
      nc
    end
  end

  @doc """
Handles any 404s encountered by the local server, either returning a dedicated 404 page (if available) or a simple 404 "not found"
"""
  def handle_not_found(conn, _opts) do
    not_found = SiteStore.get("page/404")
    if not_found do
      Plug.Conn.send_resp(conn, 404, not_found.html)
    else
      Plug.Conn.send_resp(conn, 404, "not found")
    end
  end
end

defmodule Ivy.Skel do
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

defmodule Watcher do
  @moduledoc """
Monitors relevant directories for changing files.
Issues the command to recompile said files upon change.
"""
  use GenServer

  # TODO: need watchers for each type of directory...
  # for now ignore anything except posts
  def init(_args) do
    {:ok, pid} = :file_monitor.start_link()
    {:ok, postMonRef, _path} = monitor(ConfigAgent.get(:posts))
    {:ok, pageMonRef, _path} = monitor(ConfigAgent.get(:pages))
    {:ok, templateMonRef, _path} = monitor(ConfigAgent.get(:templates))
    {:ok, staticMonRef, _path} = monitor(ConfigAgent.get(:static))
    {:ok, %{fm: pid, posts: postMonRef,
            pages: pageMonRef, templates: templateMonRef, static: staticMonRef}}
  end

  def handle_call(c, _from, state) do
    IO.inspect c, pretty: true
    {:reply, :ok, state}
  end

  def handle_cast(c, state) do
    IO.inspect c, pretty: true
    {:noreply, state}
  end

  def handle_info({:file_monitor, monRef, {:changed, path, :file, _finfo, _info}},
                  %{posts: postMonRef, pages: pageMonRef,
                    templates: templateMonRef, static: staticMonRef} = state) do
    case monRef do
      ^postMonRef ->
        if String.match?(path, ~r/\d{4}-\d{1,2}-\d{1,2}-.+/) do
          Ivy.Core.render(path, :post)
        end
      ^pageMonRef ->
        if Path.extname(path) == ".md" do
          Ivy.Core.render(path, :page)
        else
          Ivy.Core.copy_raw([path])
        end
      ^templateMonRef ->
        # recompile ALL templates due to inheritance...
        # TODO: implement
        :ok
      ^staticMonRef ->
        Ivy.Core.copy_raw([path])
    end
    {:noreply, state}
  end
  def handle_info({:file_monitor, monRef, {:found, path, :file, _finfo, _info}},
                  %{posts: postMonRef, pages: pageMonRef,
                    templates: templateMonRef, static: staticMonRef} = state) do
    # TODO: this will be called when starting. need to basically build everything initially
    case monRef do
      ^postMonRef ->
        if String.match?(path, ~r/\d{4}-\d{1,2}-\d{1,2}-.+/) do
          Ivy.Core.render(path, :post)
        end
      ^pageMonRef ->
        if Path.extname(path) == ".md" do
          Ivy.Core.render(path, :page)
        else
          Ivy.Core.copy_raw([path])
        end
      ^templateMonRef ->
        # recompile ALL templates due to inheritance...
        # TODO: implement
        :ok
      ^staticMonRef ->
        Ivy.Core.copy_raw([path])
    end
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp monitor(path) do
    :file_monitor.automonitor(path)
  end
end

defmodule TemplateStore do
  @moduledoc """
The `TemplateStore` is a cache for compiled EEx templates.

It contains the functionality necessary to expand the default templates with
@include and simple inheritance.
"""

  @content_regex ~r/<%=\s+@content\s+%>/

  @doc "Starts and links to the `TemplateStore`."
  @spec start_link() :: Agent.on_start
  def start_link() do
    Agent.start_link(fn -> HashDict.new() end, name: __MODULE__)
  end

  @doc "Puts a template into the the store."
  @spec put(String.t, Template.t) :: :ok
  def put(k, v) do
    Agent.update(__MODULE__, &Dict.put(&1, k, v))
  end

  @doc "Returns the template matching the key."
  @spec get(String.t) :: Template.t | nil
  def get(k) do
    Agent.get(__MODULE__, &Dict.get(&1, k))
  end

  @doc """
Recursively updates all template by traveling along their template hierarchie.

Run *after* you have `prep_template`ed all templates.
"""
  @spec handle_template_hierarchy!() :: :ok
  def handle_template_hierarchy!() do
    templates = Agent.get(__MODULE__, &(HashDict.values(&1)))
    Enum.each(templates, &handle_template_hierarchy/1)
  end

  @doc """
Compiles all existing template strings for efficiency.

CARE: not idempotent!
"""
  @spec compile_templates!() :: :ok
  def compile_templates!() do
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
  @spec prep_template(Path.t) :: :ok
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

  @spec handle_template_hierarchy(Template.t) :: no_return
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

  @spec parent_template(Template.t) :: Template.t | false
  defp parent_template(template) do
    pt = Keyword.get(template.meta, :layout, false)
    if pt do
      TemplateStore.get(pt)
    else
      false
    end
  end
end

alias Ivy.Paginator
alias Ivy.Post
alias Ivy.Page
alias Ivy.Template

defmodule Ivy.Core do
  @moduledoc """
`Ivy.Core` contains the majority of ivy's logic and its `main/1`.
"""

  @version Keyword.get(Mix.Project.config(), :version)
  # TODO
  # "plugin" framework
  # tests
  # error handling

  @doc "Runs a local server."
  @spec run_server(pos_integer) :: :ok
  def run_server(port) do
    {:ok, _} = Plug.Adapters.Cowboy.http Ivy.LocalServer, [], port: port
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
          GenServer.start_link(Ivy.FileWatcher, [])
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
    {:ok, _pid} = Ivy.ConfigAgent.start_link()
    {:ok, _pid} = Ivy.SiteStore.start_link()
    {:ok, _pid} = Ivy.TemplateStore.start_link()
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
      Ivy.ConfigAgent.set_config(config)
    end

    Ivy.ConfigAgent.prepend_path([:out, :posts, :templates, :includes, :static], cwd)
  end

  @doc "Parse templates, pages and posts and render them to file."
  @spec build() :: :ok | no_return
  def build() do
    start = :erlang.now()
    IO.puts "Your ivy is now growing!"

    :ok = clean_out_dir()
    _paths = copy_static_files()

    # parse local config (provide defaults)
    out_dir = Ivy.ConfigAgent.get(:out)
    if !(File.dir?(out_dir)) do
      IO.puts "Ivy needs #{out_dir} to exist and be a directory"
      System.halt(126)
    end

    # grab posts
    md_posts = Mix.Utils.extract_files([Ivy.ConfigAgent.get(:posts)], "*.md")
    md_posts = Enum.filter(md_posts, &String.match?(&1, ~r/\d{4}-\d{1,2}-\d{1,2}-.+/))

    # grab pages
    md_pages = Mix.Utils.extract_files([Ivy.ConfigAgent.get(:pages)], "*.md")
    raw_pages = Mix.Utils.extract_files([Ivy.ConfigAgent.get(:pages)], "*.html")

    # raws simply get copied
    copy_raw(raw_pages)

    # grab includes
    prep_includes()

    # templating
    templates = Mix.Utils.extract_files([Ivy.ConfigAgent.get(:templates)], "*.html")
    Enum.each(templates, &Ivy.TemplateStore.prep_template/1)
    Ivy.TemplateStore.handle_template_hierarchy!()
    Ivy.TemplateStore.compile_templates!()

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
    File.cp!(f, Ivy.ConfigAgent.get(:out))
    copy_raw(rem_f)
  end

  @doc "Removes any stale artefacts from previous runs before building."
  @spec clean_out_dir() :: :ok | no_return
  def clean_out_dir() do
    out = Ivy.ConfigAgent.get(:out)
    _paths = File.rm_rf!(out)
    File.mkdir!(out)
  end

  @doc "Copies the static dir into `:out`"
  @spec copy_static_files() :: no_return | [Path.t]
  def copy_static_files() do
    out = Ivy.ConfigAgent.get(:out)
    static = Ivy.ConfigAgent.get(:static)
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
      posts = Ivy.SiteStore.get_all_posts()

      pages = Ivy.SiteStore.get_all_pages()

      meta = Ivy.Utils.extract_meta(File.stream!(fname), :init)
      meta = Ivy.ConfigAgent.local_conf(meta)
      t = Ivy.TemplateStore.get(Keyword.get(meta, :layout, "base"))

      if ConfigAgent.get(:paginate, false) do
        fname = "index.html"
        fpath = Path.join(Ivy.ConfigAgent.get(:out), fname)
        write_index(fpath, t, Keyword.merge(meta, [posts: posts, pages: pages]))
      else
        per_page = Ivy.ConfigAgent.get(:paginate_by, 5)
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

    Ivy.SiteStore.set(%Post{uri: fname, contents: html, meta: meta})
  end
  def render(f, :page) do
    {html, meta} = parse_md(f)

    {fname, raw} = write_html(f, {html, meta})

    Ivy.SiteStore.set(%Page{uri: "page/" <> fname, html: raw, meta: meta})
  end

  # TODO: need to make next, cur and prev available as URLs not ints
  @spec write_paginated_index(Template.t, [Paginator.t],
                              Ivy.Types.meta, [Page.t]) :: :ok
  defp write_paginated_index(_, [], _, _) do
    IO.puts "Created paginated index"
  end
  defp write_paginated_index(template, [%Paginator{prev: nil} = paginator|rem], meta, pages) do
    fname = "index.html"
    fpath = Path.join(Ivy.ConfigAgent.get(:out), fname)
    write_index(fpath, template, Keyword.merge(meta, [pages: pages, paginator: paginator]))
    write_paginated_index(template, rem, meta, pages)
  end
  defp write_paginated_index(template, [%Paginator{cur: cur} = paginator|rem], meta, pages) do
    dir = Path.join(Ivy.ConfigAgent.get(:out), "page-"<> Integer.to_string(cur))
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
    incl = Ivy.ConfigAgent.get(:includes)
    if File.dir? incl do
      incls = Mix.Utils.extract_files([incl], "*.html")
      Enum.each(incls, fn inc ->
                  name = "include/" <> Path.basename(inc)
                  contents = File.read! inc
                  Ivy.TemplateStore.put(name, %Template{tpl: contents, name: name})
                  end)
    end
  end

  @spec parse_md(Path.t) :: {Ivy.Types.html, Ivy.Types.meta}
  defp parse_md(f) do
    meta = Ivy.Utils.extract_meta(File.stream!(f), :init)
    meta = Ivy.ConfigAgent.local_conf(meta)
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
    t = Ivy.TemplateStore.get(Keyword.get(meta, :layout, "base"))
    data = Keyword.merge(meta, [content: html])

    {html, _ctx} = Code.eval_quoted(t.tpl, [assigns: data], __ENV__)

    fname = Path.basename(f, ".md") <> ".html"
    out_path = Path.join(Ivy.ConfigAgent.get(:out), fname)

    File.write!(out_path, html)

    {fname, html}
  end
end

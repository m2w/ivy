alias Ivy.Template

defmodule Ivy.TemplateStore do
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
        t = get("include/" <> m)
        if t do
          t.tpl
        else
          ""
        end
      end)

    put(name, %Template{tpl: template, meta: meta, name: name})
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
      put(t.name, t)
      handle_template_hierarchy(t)
    end
  end

  @spec parent_template(Template.t) :: Template.t | false
  defp parent_template(template) do
    pt = Keyword.get(template.meta, :layout, false)
    if pt do
      get(pt)
    else
      false
    end
  end
end

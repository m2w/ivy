defmodule Ivy.ConfigAgent do
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

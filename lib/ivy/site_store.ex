alias Ivy.Post
alias Ivy.Page

defmodule Ivy.SiteStore do
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
    Enum.filter(get_all_content(), fn c ->
      c.__struct__ == Post end)
  end

  @spec get_all_content() :: HashDict.t
  defp get_all_content() do
    Agent.get(__MODULE__, fn state -> Dict.values(state) end)
  end
end

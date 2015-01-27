defmodule Ivy.Types do
  @moduledoc """
Contains abstract type definitions.
"""

  @type markdown :: String.t
  @type html :: String.t
  @type meta :: Keyword.t
  @type nillable_int :: Integer.t | nil
end

defmodule Ivy.Page do
  @moduledoc """
A Page refers a single page on an ivy site. They differ from posts only
in their URLs.
"""

  defstruct html: "", meta: [], uri: ""
  @type t :: %Ivy.Page{html: Ivy.Types.html, meta: Ivy.Types.meta, uri: String.t}
end

defmodule Ivy.Post do
  @moduledoc """
Posts represent markdown documents that form the main content of an ivy site.

They are composed of meta data, the content itself and a URI.
"""

  defstruct contents: "", meta: [], uri: ""
  @type t :: %Ivy.Post{contents: String.t, meta: Ivy.Types.meta, uri: String.t}
end

defmodule Ivy.Template do
  @moduledoc """
Templates are parsed markdown documents.

They can handle @include directives to include shared snippets and
implement a simple form of inheritance.
"""

  defstruct tpl: "", meta: [], name: ""
  @type t :: %Ivy.Template{tpl: String.t, meta: Ivy.Types.meta, name: String.t}
end

defmodule Ivy.Paginator do
  @moduledoc """
A wrapper for paginated items.

Contains links to itself, previous and following items.
"""

  defstruct prev: nil, cur: nil, next: nil, per_page: 5, items: []
  @type t :: %Ivy.Paginator{prev: Ivy.Types.nillable_int, cur: non_neg_integer,
                            next: Ivy.Types.nillable_int, per_page: pos_integer,
                            items: [Ivy.Post.t]}
end

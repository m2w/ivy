defmodule Ivy.LocalServer do
  @docmodule """
`LocalServer` is a simple plug based server to view your site locally.

It is soley intended for development.
"""

  use Plug.ErrorHandler

  def init(options) do
    options
  end

  def call(conn, _opts) do
    opts = Plug.Static.init([gzip: true, at: "/", from: Ivy.ConfigAgent.get(:out)])
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
    not_found = Ivy.SiteStore.get("page/404")
    if not_found do
      Plug.Conn.send_resp(conn, 404, not_found.html)
    else
      Plug.Conn.send_resp(conn, 404, "not found")
    end
  end
end

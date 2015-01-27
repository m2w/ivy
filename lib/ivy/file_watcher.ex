defmodule Ivy.FileWatcher do
  @moduledoc """
Monitors relevant directories for changing files.
Issues the command to recompile said files upon change.
"""
  use GenServer

  # TODO: need watchers for each type of directory...
  # for now ignore anything except posts
  def init(_args) do
    {:ok, pid} = :file_monitor.start_link()
    {:ok, postMonRef, _path} = monitor(Ivy.ConfigAgent.get(:posts))
    {:ok, pageMonRef, _path} = monitor(Ivy.ConfigAgent.get(:pages))
    {:ok, templateMonRef, _path} = monitor(Ivy.ConfigAgent.get(:templates))
    {:ok, staticMonRef, _path} = monitor(Ivy.ConfigAgent.get(:static))
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

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

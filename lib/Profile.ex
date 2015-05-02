defmodule Profile do
  import ExProf.Macro

  @doc "analyze with profile macro"
  def analyze do
    profile do
      Ivy.Core.main([])
    end
  end
end

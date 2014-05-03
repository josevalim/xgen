defmodule Xgen.Mixfile do
  use Mix.Project

  def project do
    [app: :xgen,
     version: "0.1.0",
     elixir: "~> 0.13.1",
     deps: deps]
  end

  def application do
    [applications: []]
  end

  defp deps do
    []
  end
end

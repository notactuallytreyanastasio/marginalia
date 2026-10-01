defmodule Temper.Std.MixProject do
  use Mix.Project

  def project do
    [app: :temper_std, version: "0.1.0", elixir: "~> 1.15", deps: deps(), elixirc_paths: elixirc_paths(Mix.env())]
  end

  defp deps do
    [{:temper_core, path: "../temper-core"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end

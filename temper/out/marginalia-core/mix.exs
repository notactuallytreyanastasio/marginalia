defmodule Temper.MarginaliaCore.MixProject do
  use Mix.Project

  def project do
    [app: :temper_marginalia_core, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end

  defp deps do
    [{:temper_core, path: "../temper-core"}]
  end
end

defmodule AshEyg.Domain do
  @eyg %Spark.Dsl.Section{
    name: :eyg,
    describe: "Domain-level configuration for AshEyg.",
    examples: [
      """
      eyg do
        name "Helpdesk"
      end
      """
    ],
    schema: [
      name: [
        type: :string,
        doc:
          "The prefix of every effect label from this domain. Defaults to the last segment of the domain module."
      ]
    ]
  }

  @moduledoc """
  Extension that exposes the actions of a domain's resources to EYG programs as effects.

  Only resources that also use `AshEyg.Resource` are exposed.
  """

  use Spark.Dsl.Extension, sections: [@eyg]
end

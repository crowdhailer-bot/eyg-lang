defmodule AshEyg.Resource do
  @eyg %Spark.Dsl.Section{
    name: :eyg,
    describe: "Resource-level configuration for AshEyg.",
    examples: [
      """
      eyg do
        name "Ticket"
        expose? true
      end
      """
    ],
    schema: [
      name: [
        type: :string,
        doc:
          "The part of an effect label naming this resource. Defaults to the last segment of the resource module."
      ],
      expose?: [
        type: :boolean,
        default: true,
        doc: "Whether to expose this resource's actions as effects."
      ]
    ]
  }

  @moduledoc """
  Extension that exposes a resource's actions to EYG programs as effects.

  Used with `AshEyg.Domain` on the resource's domain.
  Every action becomes an effect labelled by domain, resource and action, i.e. `SupportTicketOpen`.
  """

  use Spark.Dsl.Extension, sections: [@eyg]
end

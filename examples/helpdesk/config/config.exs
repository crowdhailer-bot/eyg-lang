import Config

# This tells Ash about your domain, which is used to find
# available resource and actions
config :helpdesk, :ash_domains, [Helpdesk.Support, Helpdesk.Scripting]

config :helpdesk,
       :standard_library,
       Path.expand("../../../eyg_packages/standard/index.eyg.json", __DIR__)

config :helpdesk, HelpdeskWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Helpdesk.PubSub,
  render_errors: [formats: [html: HelpdeskWeb.ErrorHTML], layout: false],
  live_view: [signing_salt: "oZuqiClsm23daSJ"]

config :phoenix, :json_library, Jason

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  many_to_many_destroy_destination_on_match?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

import_config "#{config_env()}.exs"

import Config
config :ash, policies: [show_policy_breakdowns?: true]

config :helpdesk, HelpdeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  secret_key_base: "//sQCdToNPurOUBrpr3eUOlP3OGLA4zrDNJepTtNOyZ7gYbaJczqZqg2CdIoy10n"

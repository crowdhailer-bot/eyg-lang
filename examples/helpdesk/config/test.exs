import Config
config :ash, policies: [show_policy_breakdowns?: true]

config :helpdesk, HelpdeskWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ETIUhH1CqwgP5dxWfGSGMzx1P9G8cwlwsri4zZtH7plsWVMuZ7PMkTM3FGcSioTL",
  server: false

import Config

if config_env() == :test do
  config :ash, default_string_length_count: :codepoints, disable_async?: true
  config :ash_eyg, :ash_domains, [AshEyg.Test.Support]
  config :logger, level: :warning
end

import Config

if config_env() == :test do
  config :ash, default_string_length_count: :codepoints, disable_async?: true
  config :ash_eyg, :ash_domains, [AshEyg.Test.Support, AshEyg.Test.Scripts]
  config :logger, level: :warning
end

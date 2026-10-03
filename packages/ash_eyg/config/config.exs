import Config

if config_env() == :test do
  config :ash, default_string_length_count: :codepoints, disable_async?: true
  config :logger, level: :warning
end

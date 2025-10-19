import Config

config :argos,
  logger: Argos.Logger.Default,
  tui_detector: Argos.TuiDetector.Default,
  env: config_env()

# Configuración del logger
config :logger,
  backends: [Argos.Logger]

if config_env() == :dev do
  config :logger, level: :debug
end

if config_env() == :test do
  config :logger, level: :warn
end

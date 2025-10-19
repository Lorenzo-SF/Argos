ExUnit.start()

# Configurar entorno de test
Application.put_env(:argos, :env, :test)
Application.put_env(:argos, :tui_detector, Argos.TuiDetector.Default)

# Asegurar que el logger esté configurado
:logger.add_handler(Argos.Logger, Argos.Logger, %{})
:logger.set_primary_config(:level, :warn)

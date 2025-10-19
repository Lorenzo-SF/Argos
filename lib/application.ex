defmodule Argos.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    setup_logger()

    children = [
      # Otros workers/supervisors pueden ir aquí
    ]

    opts = [strategy: :one_for_one, name: Argos.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_logger do
    # Configurar el logger de Elixir para usar nuestro handler
    :logger.add_handler(Argos.Logger, Argos.Logger, %{})

    # Configurar nivel según entorno
    level =
      case Application.get_env(:argos, :env, :dev) do
        :prod -> :warning
        :test -> :warning
        _ -> :debug
      end

    :logger.set_primary_config(:level, level)
  end
end

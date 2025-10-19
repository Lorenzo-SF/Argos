defmodule Argos do
  @moduledoc """
  Módulo principal de Argos.
  """

  @doc """
  Obtiene la implementación actual del logger.
  """
  def current_logger do
    Application.get_env(:argos, :logger, Argos.Logger.Default)
  end

  @doc """
  Logea un mensaje usando el logger configurado.
  """
  def log(level, message, metadata \\ []) do
    logger = current_logger()
    logger.log(level, message, metadata)
  end

  @doc """
  Logea un resultado de comando usando el logger configurado.
  """
  def log_command(%Argos.Structs.CommandResult{} = result) do
    logger = current_logger()

    if function_exported?(logger, :log_command, 1) do
      logger.log_command(result)
    else
      log(:info, "Command: #{result.command} (exit: #{result.exit_code})",
        command: result.command,
        exit_code: result.exit_code,
        duration: result.duration,
        success?: result.success?
      )
    end
  end

  @doc """
  Logea un resultado de tarea usando el logger configurado.
  """
  def log_task(%Argos.Structs.TaskResult{} = result) do
    logger = current_logger()

    if function_exported?(logger, :log_task, 1) do
      logger.log_task(result)
    else
      level = if result.success?, do: :success, else: :error

      log(
        level,
        "Task: #{result.task_name} - #{if result.success?, do: "SUCCESS", else: "FAILED"}",
        task_name: result.task_name,
        duration: result.duration,
        success?: result.success?,
        error: result.error
      )
    end
  end

  @doc """
  Verifica si estamos en modo TUI.
  """
  def tui_mode? do
    Argos.TuiDetector.tui_mode?()
  end
end

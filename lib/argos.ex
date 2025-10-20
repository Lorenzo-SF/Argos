defmodule Argos do
  @moduledoc """
  Argos is a system command execution and task orchestration library.

  This is the main module that provides access to Argos's core functionality:
  - Command execution with structured results
  - Asynchronous task management
  - Structured logging system
  - TUI mode detection

  ## Examples

      # Logging a simple message
      Argos.log(:info, "Application started", version: "1.0.0")

      # Logging a command result
      result = Argos.Command.exec("ls -la")
      Argos.log_command(result)

      # Checking if we're in TUI mode
      if Argos.tui_mode?() do
        # Handle TUI-specific logic
      else
        # Handle console output
      end
  """

  @doc """
  Gets the current logger implementation.

  The logger can be configured via the `:logger` option in the `:argos` application environment.
  By default, returns `Argos.Logger.Default`.

  ## Examples

      logger = Argos.current_logger()
      logger.log(:info, "Hello, world!", [])
  """
  def current_logger do
    Application.get_env(:argos, :logger, Argos.Logger.Default)
  end

  @doc """
  Logs a message using the configured logger.

  ## Parameters

    * `level` - The log level (e.g., `:info`, `:warn`, `:error`, `:success`)
    * `message` - The message to log (string or any term that can be inspected)
    * `metadata` - Optional keyword list of metadata to include with the log

  ## Examples

      Argos.log(:info, "User logged in", user_id: 123, ip: "192.168.1.1")
      Argos.log(:error, "Database connection failed", error: "timeout")
  """
  def log(level, message, metadata \\ []) do
    logger = current_logger()
    logger.log(level, message, metadata)
  end

  @doc """
  Logs a command result using the configured logger.

  If the configured logger implements the `log_command/1` callback, it will use that.
  Otherwise, it falls back to a standard log format.

  ## Parameters

    * `result` - An `Argos.Structs.CommandResult` struct

  ## Examples

      result = Argos.Command.exec("ls -la")
      Argos.log_command(result)
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
  Logs a task result using the configured logger.

  If the configured logger implements the `log_task/1` callback, it will use that.
  Otherwise, it falls back to a standard log format.

  ## Parameters

    * `result` - An `Argos.Structs.TaskResult` struct

  ## Examples

      result = Argos.AsyncTask.run_single("my_task", fn -> "task completed" end)
      Argos.log_task(result)
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
  Checks if the application is running in TUI (Text User Interface) mode.

  Uses the configured TUI detector to determine the mode.

  ## Examples

      if Argos.tui_mode?() do
        # Use TUI-specific output formatting
        display_in_tui_window("Operation complete")
      else
        # Use regular console output
        IO.puts("Operation complete")
      end
  """
  def tui_mode? do
    Argos.TuiDetector.tui_mode?()
  end
end

defmodule Argos.Logger.Behaviour do
  @moduledoc """
  Behaviour for implementing custom loggers in Argos.

  This behaviour defines the interface that custom logger implementations
  must follow to work with the Argos logging system. It allows for
  pluggable logging backends that can format, filter, and output logs
  according to specific requirements.

  ## Implementing the Behaviour

  To create a custom logger, implement this behaviour:

      defmodule MyCustomLogger do
        @behaviour Argos.Logger.Behaviour

        @impl true
        def log(level, message, metadata) do
          # Your logging implementation
          :ok
        end

        @impl true
        def log_command(%Argos.Structs.CommandResult{} = result) do
          # Your command logging implementation
          :ok
        end

        @impl true
        def log_task(%Argos.Structs.TaskResult{} = result) do
          # Your task logging implementation
          :ok
        end
      end

  Then configure it in your application:

      config :argos,
        logger: MyCustomLogger

  ## Examples

      # Implementing a simple console logger
      defmodule ConsoleLogger do
        @behaviour Argos.Logger.Behaviour

        @impl true
        def log(level, message, metadata) do
          timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
          IO.puts("[#{timestamp}] [#{level}] #{message} #{inspect(metadata)}")
          :ok
        end

        @impl true
        def log_command(%Argos.Structs.CommandResult{} = result) do
          log(:info, "Command executed: #{result.command}", [
            exit_code: result.exit_code,
            duration: result.duration
          ])
          :ok
        end

        @impl true
        def log_task(%Argos.Structs.TaskResult{} = result) do
          status = if result.success?, do: "SUCCESS", else: "FAILED"
          log(:info, "Task completed: #{result.task_name} - #{status}", [
            duration: result.duration
          ])
          :ok
        end
      end
  """

  @type level :: :debug | :info | :warn | :error | :critical | :emergency | :success | :notice

  @doc """
  Logs a message with level and metadata.

  This is the primary logging function that all implementations must provide.
  It receives a log level, message, and optional metadata to log.

  ## Parameters

    * `level` - The log level (e.g., `:info`, `:warn`, `:error`)
    * `message` - The message to log (can be any term that can be inspected if needed)
    * `metadata` - Keyword list of additional metadata to include with the log

  ## Returns

    `:ok` to indicate successful logging

  ## Examples

      MyLogger.log(:info, "User logged in", user_id: 123, ip: "192.168.1.1")
      MyLogger.log(:error, "Database connection failed", error: "timeout")
  """
  @callback log(level :: level(), message :: any(), metadata :: keyword()) :: :ok

  @doc """
  Logs the result of an executed command.

  This optional callback allows for specialized formatting of command execution results.
  If not implemented, the default behavior falls back to the main `log/3` function.

  ## Parameters

    * `command_result` - An `Argos.Structs.CommandResult` struct

  ## Returns

    `:ok` to indicate successful logging

  ## Examples

      result = Argos.Command.exec("ls -la")
      MyLogger.log_command(result)
  """
  @callback log_command(command_result :: Argos.Structs.CommandResult.t()) :: :ok

  @doc """
  Logs the result of an asynchronous task.

  This optional callback allows for specialized formatting of task execution results.
  If not implemented, the default behavior falls back to the main `log/3` function.

  ## Parameters

    * `task_result` - An `Argos.Structs.TaskResult` struct

  ## Returns

    `:ok` to indicate successful logging

  ## Examples

      result = Argos.AsyncTask.run_single("backup", "tar -czf backup.tar.gz /home/user/docs")
      MyLogger.log_task(result)
  """
  @callback log_task(task_result :: Argos.Structs.TaskResult.t()) :: :ok

  @optional_callbacks log_command: 1, log_task: 1
end

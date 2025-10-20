defmodule Argos.Command do
  @moduledoc """
  Provides shell command execution capabilities with structured results.

  This module offers various ways to execute system commands, capturing their
  output, exit codes, and execution duration. All command executions return
  an `Argos.Structs.CommandResult` struct for consistent handling.

  ## Features

  - Execute commands with automatic logging
  - Support for raw, silent, interactive, and sudo command execution
  - Structured result handling with duration tracking
  - Automatic caller metadata collection
  - Timeout handling for long-running commands
  - Process management utilities

  ## Examples

      # Simple command execution
      result = Argos.Command.exec("ls -la")

      # Execute with options
      result = Argos.Command.exec("git status", stderr_to_stdout: false)

      # Raw execution without extra logging
      {output, exit_code} = Argos.Command.exec_raw("pwd")

      # Execute with sudo privileges
      result = Argos.Command.exec_sudo("systemctl restart nginx")

      # Silent execution (output redirected to /dev/null)
      exit_code = Argos.Command.exec_silent("some_command")
  """

  alias Argos.Structs.CommandResult

  @shell_timeout 30_000
  @shell Application.compile_env(:argos, :shell, "/bin/zsh")

  # ---------------- API PÚBLICA SIMPLIFICADA ----------------
  @doc """
  Executes a command and returns a structured CommandResult.

  The command is executed through the system shell (default: `/bin/zsh`).
  Results are automatically logged with metadata about the caller.
  Execution duration is measured and included in the result.

  ## Parameters

    * `command` - The command to execute as a string, or a list of [command | arguments]
    * `opts` - Keyword list of options (see `System.cmd/3` for supported options)

  ## Options

    * `:stderr_to_stdout` - Redirect stderr to stdout (default: `true`)
    * `:halt` - Halt the system if the command fails with exit code other than 0 or 1 (default: `false`)

  ## Returns

    An `Argos.Structs.CommandResult` struct containing:
    * `command` - The executed command
    * `args` - Command arguments
    * `output` - Command output
    * `exit_code` - Exit code (0 for success)
    * `duration` - Execution time in milliseconds
    * `success?` - Boolean indicating success (exit_code == 0)
    * `error` - Error message if any

  ## Examples

      result = Argos.Command.exec("ls -la")
      if result.success? do
        IO.puts("Command output: \#{result.output}")
      else
        IO.puts("Command failed with exit code: \#{result.exit_code}")
      end

      # Execute with arguments as a list
      result = Argos.Command.exec(["ls", "-la", "/tmp"])
  """
  def exec(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:normal, command, opts)
  end

  @doc """
  Executes a command and returns a tuple {output, exit_code} without additional logging.

  This function provides a raw interface similar to `System.cmd/3` but with
  the convenience of using the configured shell for string commands.

  ## Parameters

    * `command` - The command to execute as a string, or a list of [command | arguments]
    * `opts` - Keyword list of options (see `System.cmd/3` for supported options)

  ## Returns

    A tuple `{output, exit_code}` where:
    * `output` - The command output as a string
    * `exit_code` - The command exit code (0 for success)

  ## Examples

      {output, 0} = Argos.Command.exec_raw("echo 'Hello, World!'")
      {_, exit_code} = Argos.Command.exec_raw("ls /nonexistent/path")
  """
  def exec_raw(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:raw, command, opts)
  end

  @doc """
  Executes a command redirecting output to /dev/null.

  This function runs the command but suppresses all output. It returns only
  the exit code of the command, useful for operations where you only care
  about success/failure.

  ## Parameters

    * `command` - The command to execute as a string
    * `opts` - Keyword list of options (see `System.cmd/3` for supported options)

  ## Returns

    The exit code of the command execution (0 for success)

  ## Examples

      exit_code = Argos.Command.exec_silent("touch /tmp/myfile")
      if exit_code == 0 do
        IO.puts("File created successfully")
      else
        IO.puts("Failed to create file")
      end
  """
  def exec_silent(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:silent, command, opts)
  end

  @doc """
  Executes a command in interactive mode.

  This function is designed for commands that require user interaction,
  such as editors, interactive shells, or commands that need user input.
  It attempts to use the `script` utility if available for better
  interactive handling.

  ## Parameters

    * `command` - The command to execute as a string
    * `opts` - Keyword list of options

  ## Options

    * `:interactive` - Set to true to enable interactive mode (default: `true`)
    * `:halt` - Halt the system if the command fails (default: `false`)

  ## Returns

    An `Argos.Structs.CommandResult` struct

  ## Examples

      result = Argos.Command.exec_interactive("vim /tmp/file.txt")
      result = Argos.Command.exec_interactive("python -c \"input('Press enter: ')\"")
  """
  def exec_interactive(command, opts \\ []) do
    opts = Keyword.put_new(opts, :interactive, true)
    __exec__(:interactive, command, opts)
  end

  @doc """
  Executes a command with superuser privileges using sudo.

  This function logs a warning when sudo execution is attempted for security awareness.
  It handles sudo execution with proper argument formatting and environment setup.

  ## Parameters

    * `command` - The command to execute as a string
    * `opts` - Keyword list of options

  ## Options

    * `:interactive` - Enable interactive mode for sudo (default: `false`)
    * `:stderr_to_stdout` - Redirect stderr to stdout (default: `true`)
    * `:halt` - Halt the system if the command fails (default: `false`)

  ## Returns

    An `Argos.Structs.CommandResult` struct

  ## Examples

      result = Argos.Command.exec_sudo("systemctl restart nginx")
      result = Argos.Command.exec_sudo("apt-get update", interactive: true)
  """
  def exec_sudo(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:sudo, command, opts)
  end

  # ---------------- IMPLEMENTACIÓN INTERNA ----------------
  def __exec__(:raw, command, opts) do
    case command do
      cmd_list when is_list(cmd_list) and length(cmd_list) > 0 ->
        [cmd_head | cmd_tail] = cmd_list
        System.cmd(cmd_head, cmd_tail, opts)

      cmd_string when is_binary(cmd_string) ->
        System.cmd(@shell, ["-c", cmd_string], opts)

      _ ->
        System.cmd(@shell, ["-c", to_string(command)], opts)
    end
  end

  def __exec__(:normal, command, opts) do
    {halt?, opts} = Keyword.pop(opts, :halt, false)
    start_time = System.monotonic_time(:millisecond)

    {output, exit_code} = __exec__(:raw, command, opts)
    duration = System.monotonic_time(:millisecond) - start_time

    result = %CommandResult{
      command: @shell,
      args: ["-c", command],
      output: output,
      exit_code: exit_code,
      duration: duration,
      success?: exit_code == 0,
      error: nil
    }

    # Log automático con metadata del caller
    __log_result__(command, result, get_caller_metadata())

    __handle_halt__(result, halt?)
    result
  end

  def __exec__(:silent, command, opts) do
    result = __exec__(:normal, "#{command} > /dev/null 2>&1", opts)
    result.exit_code
  end

  def __exec__(:interactive, command, opts) do
    halt? = Keyword.get(opts, :halt, false)
    start_time = System.monotonic_time(:millisecond)

    case System.find_executable("script") do
      nil ->
        port =
          Port.open({:spawn_executable, System.find_executable(@shell)}, [
            :binary,
            {:args, ["-c", command]},
            :exit_status,
            :stderr_to_stdout
          ])

        result = __collect_output__(command, port, "", start_time)
        __handle_halt__(result, halt?)

      script_path ->
        args = ["-q", "/dev/null", @shell, "-c", command]

        port =
          Port.open({:spawn_executable, script_path}, [
            :binary,
            :stream,
            :exit_status,
            :stderr_to_stdout,
            {:args, args}
          ])

        command
        |> __collect_output__(port, "", start_time)
        |> __handle_halt__(halt?)
    end
  end

  def __exec__(:sudo, command, opts) do
    interactive? = Keyword.get(opts, :interactive, false)
    halt? = Keyword.get(opts, :halt, false)
    start_time = System.monotonic_time(:millisecond)

    Argos.log(:warning, "SUDO command execution attempted", command: command)

    executable = System.find_executable("sudo")

    if executable do
      args = get_interactive_args(command, interactive?)

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :stream,
          :exit_status,
          :stderr_to_stdout,
          {:args, args},
          {:env, [{"SUDO_ASKPASS", "/usr/bin/ssh-askpass"}]}
        ])

      command
      |> __collect_output__(port, "", start_time)
      |> __handle_halt__(halt?)
    else
      duration = System.monotonic_time(:millisecond) - start_time

      %CommandResult{
        command: command,
        args: [],
        output: "sudo command not found",
        exit_code: 127,
        duration: duration,
        success?: false,
        error: "sudo command not found"
      }
    end
  end

  # ---------------- HELPER: CAPTURAR METADATA DEL CALLER ----------------
  defp get_caller_metadata do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        # Buscar el primer frame que no sea de Argos.Command
        caller_frame =
          Enum.find(stacktrace, fn
            {Argos.Command, _, _, _} -> false
            {_, _, _, _} -> true
            _ -> false
          end) || List.first(stacktrace)

        case caller_frame do
          {module, function, arity, [file: file, line: line]} ->
            %{
              module: module,
              function: "#{function}/#{arity}",
              file: file,
              line: line
            }

          {module, function, arity, _} ->
            %{
              module: module,
              function: "#{function}/#{arity}",
              file: "unknown",
              line: 0
            }

          _ ->
            %{module: "unknown", function: "unknown/0", file: "unknown", line: 0}
        end

      _ ->
        %{module: "unknown", function: "unknown/0", file: "unknown", line: 0}
    end
  end

  # ---------------- HELPER: LOGGING MEJORADO ----------------
  defp __log_result__(command, %CommandResult{} = result, caller_metadata) do
    # Usar la nueva API de logging de Argos
    metadata =
      [
        command: command,
        exit_code: result.exit_code,
        duration: result.duration,
        success?: result.success?,
        output_length: String.length(result.output || "")
      ] ++ Map.to_list(caller_metadata)

    if result.success? do
      Argos.log(:info, "Command executed: #{command}", metadata)
    else
      Argos.log(:error, "Command failed: #{command}", metadata)
    end

    # También loguear el resultado estructurado
    Argos.log_command(result)
  end

  # ---------------- MANTENER FUNCIONES EXISTENTES (modificadas) ----------------
  defp get_interactive_args(command, false), do: ["-A", @shell, "-c", command]

  defp get_interactive_args(command, true) do
    case System.find_executable("script") do
      nil ->
        ["-A", @shell, "-c", command]

      script_path ->
        [
          "-A",
          script_path,
          "-q",
          "/dev/null",
          @shell,
          "-c",
          command
        ]
    end
  end

  @doc """
  Halts the system with the specified exit code.

  This function terminates the Erlang VM and does not return.
  Use with caution as this will stop the entire application.

  ## Parameters

    * `code` - The exit code to use (default: 0 for success)

  ## Examples

      # Exit with success code
      Argos.Command.halt()

      # Exit with error code
      Argos.Command.halt(1)
  """
  @dialyzer {:no_return, halt: 0}
  @dialyzer {:no_return, halt: 1}
  def halt(code \\ 0) do
    System.halt(code)
  end

  def __handle_halt__(%CommandResult{exit_code: code, output: msg}, true)
      when code not in [0, 1] do
    Argos.log(:error, "Command failed, halting system",
      exit_code: code,
      output: String.trim(msg || "")
    )

    halt()
  end

  def __handle_halt__(result, _), do: result

  defp __collect_output__(command, port, acc, start_time) when is_integer(start_time) do
    actual_start_time = start_time

    receive do
      {^port, {:data, data}} ->
        __collect_output__(command, port, acc <> data, actual_start_time)

      {^port, {:exit_status, code}} ->
        duration = System.monotonic_time(:millisecond) - actual_start_time

        result = %CommandResult{
          command: command,
          args: [],
          output: acc,
          exit_code: code,
          duration: duration,
          success?: code == 0,
          error: nil
        }

        __log_result__(command, result, get_caller_metadata())
        result
    after
      @shell_timeout ->
        if is_port(port), do: Port.close(port)

        result = %CommandResult{
          command: command,
          args: [],
          output: acc,
          exit_code: 1,
          duration: System.monotonic_time(:millisecond) - actual_start_time,
          success?: false,
          error: "Timeout after #{@shell_timeout}ms"
        }

        __log_result__(command, result, get_caller_metadata())
        result
    end
  end

  # ---------------- MANTENER FUNCIONES DE PROCESOS ----------------
  @doc """
  Processes a command response code into a structured format.

  This function takes an exit code and returns a map with code, message, and type
  based on the exit code value.

  ## Parameters

    * `code` - The exit code to process
    * `opts` - Keyword list of options for custom messages
      * `:success_message` - Message for exit code 0 (default: "")
      * `:warning_message` - Message for exit code 1 (default: "")
      * `:error_message` - Message for other codes (default: "")

  ## Returns

    A map with:
    * `:code` - The original exit code
    * `:message` - Normalized message as a list of lines
    * `:type` - The message type (:success, :warning, or :error)

  ## Examples

      response = Argos.Command.process_response(0, success_message: "Operation completed")
      # Returns: %{code: 0, message: ["Operation completed"], type: :success}
  """
  def process_response(code, opts \\ []) do
    message =
      code
      |> get_message(opts)
      |> normalize_response()

    %{
      code: code,
      message: message,
      type: get_message_type(code)
    }
  end

  defp normalize_response(message, default_value \\ "") do
    (message || default_value)
    |> to_string()
    |> String.trim()
    |> String.split("\\n", trim: true)
  end

  defp get_message(0, opts), do: Keyword.get(opts, :success_message, "")
  defp get_message(1, opts), do: Keyword.get(opts, :warning_message, "")
  defp get_message(_, opts), do: Keyword.get(opts, :error_message, "")

  defp get_message_type(0), do: :success
  defp get_message_type(1), do: :warning
  defp get_message_type(_), do: :error

  # ---------------- FUNCIONES DE KILL CORREGIDAS ----------------
  @doc """
  Kills a process by name using the kill command.

  This function uses pgrep to find processes matching the name and kills them
  with SIGTERM. Includes safety checks to prevent command injection.

  ## Parameters

    * `process_name` - The name of the process to kill (string)

  ## Returns

    An `Argos.Structs.CommandResult` struct

  ## Examples

      result = Argos.Command.kill_process("nginx")
      if result.success? do
        IO.puts("Nginx killed successfully")
      else
        IO.puts("Failed to kill nginx: \#{result.output}")
      end
  """
  def kill_process(process_name) when is_binary(process_name) do
    if String.length(process_name) > 0 and
         String.match?(process_name, ~r/^[a-zA-Z0-9_.-]+$/) do
      # Usar exec en lugar de exec_raw para evitar problemas
      exec("pgrep -f #{process_name} | head -10 | xargs kill -TERM")
    else
      %CommandResult{
        command: "kill",
        args: [process_name],
        output: "Invalid process name",
        exit_code: 1,
        duration: 0,
        success?: false,
        error: "Invalid process name"
      }
    end
  end

  def kill_process(_) do
    CommandResult.failure(
      "kill",
      [],
      "Process name must be a string",
      1,
      0,
      "Process name must be a string"
    )
  end

  @doc """
  Kills multiple processes by name using a more robust approach.

  This function attempts to gracefully kill processes first with SIGTERM,
  then forcefully with SIGKILL if needed. It logs the operation and
  returns detailed results for each process.

  ## Parameters

    * `process_names` - List of process names to kill

  ## Returns

    A list of tuples where each tuple contains `{process_name, status}`.
    Status can be:
    * `:killed` - Process was successfully killed
    * `:not_found` - Process was not found
    * `{:error, reason}` - Error occurred while killing process

  ## Examples

      results = Argos.Command.kill_processes_by_name(["nginx", "apache", "redis"])
      for {name, status} <- results do
        case status do
          :killed -> IO.puts("\#{name} was killed")
          :not_found -> IO.puts("\#{name} was not found")
          {:error, reason} -> IO.puts("Error killing \#{name}: \#{reason}")
        end
      end
  """
  def kill_processes_by_name(process_names) when is_list(process_names) do
    Argos.log(:info, "Killing processes", process_names: process_names)

    Enum.map(process_names, fn process_name ->
      case kill_process_robust(process_name) do
        :ok -> {process_name, :killed}
        :not_found -> {process_name, :not_found}
        {:error, reason} -> {process_name, {:error, reason}}
      end
    end)
  end

  defp kill_process_robust(process_name) do
    with {:kill_term, %CommandResult{exit_code: 0}} <-
           do_kill_term(process_name),
         {:pgrep, %CommandResult{exit_code: pgrep_code}} <-
           do_pgrep(process_name),
         {:pkill, %CommandResult{exit_code: 0}} <- do_pkill(process_name, pgrep_code) do
      :ok
    else
      {:kill_term, %CommandResult{exit_code: 1}} ->
        :not_found

      {:kill_term, %CommandResult{output: error, exit_code: code}} ->
        Argos.log(:error, "Error killing process",
          process_name: process_name,
          error: error,
          exit_code: code
        )

        {:error, :kill_term_command_failed}

      {:pkill, %CommandResult{exit_code: exit_code}} when exit_code != 0 ->
        {:error, :pkill_failed}
    end
  end

  defp do_kill_term(process_name) do
    # Usar System.cmd directamente sin opciones problemáticas
    {output, exit_code} = System.cmd("pkill", ["-TERM", process_name])

    {:kill_term,
     %CommandResult{
       command: "pkill",
       args: ["-TERM", process_name],
       output: output,
       exit_code: exit_code,
       duration: 0,
       success?: exit_code == 0
     }}
  end

  defp do_pgrep(process_name) do
    Process.sleep(2000)
    {output, exit_code} = System.cmd("pgrep", [process_name])

    {:pgrep,
     %CommandResult{
       command: "pgrep",
       args: [process_name],
       output: output,
       exit_code: exit_code,
       duration: 0,
       success?: exit_code == 0
     }}
  end

  defp do_pkill(_process_name, 1), do: {:pkill, %CommandResult{exit_code: 0}}

  defp do_pkill(process_name, 0) do
    {output, exit_code} = System.cmd("pkill", ["-KILL", process_name])

    {:pkill,
     %CommandResult{
       command: "pkill",
       args: ["-KILL", process_name],
       output: output,
       exit_code: exit_code,
       duration: 0,
       success?: exit_code == 0
     }}
  end
end

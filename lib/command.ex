defmodule Argos.Command do
  @moduledoc """
  Sistema de ejecución de comandos shell con soporte para diferentes modos.

  Proporciona macros y funciones para ejecutar comandos del sistema con control
  granular sobre la salida, el modo de ejecución y el manejo de errores.

  ## Características

  - Múltiples modos de ejecución (normal, silencioso, interactivo, sudo)
  - Resultados estructurados con duración y códigos de salida
  - Logging automático de comandos ejecutados
  - Soporte para timeouts configurables
  - Manejo de procesos y señales
  - Ejecución segura de comandos con validación

  ## Modos de Ejecución

  ### Normal (`exec!/2`)
  Ejecuta un comando y devuelve un struct CommandResult con toda la información.

      result = exec!("ls -la")
      if result.success? do
        IO.puts("Salida: #{result.output}")
      end

  ### Raw (`exec_raw!/2`)
  Ejecuta un comando y devuelve una tupla {output, exit_code} sin logging.

      {output, code} = exec_raw!("git status")

  ### Silencioso (`exec_silent!/2`)
  Ejecuta un comando redirigiendo toda la salida a /dev/null.

      code = exec_silent!("some_quiet_command")

  ### Interactivo (`exec_interactive!/2`)
  Ejecuta un comando permitiendo interacción en tiempo real.

      result = exec_interactive!("vim archivo.txt")

  ### Sudo (`exec_sudo!/2`)
  Ejecuta un comando con privilegios de superusuario.

      result = exec_sudo!("systemctl restart nginx")

  ## Opciones Comunes

  - `:timeout` - Timeout en milisegundos (default: 30_000)
  - `:stderr_to_stdout` - Redirige stderr a stdout (default: true)
  - `:halt` - Termina el programa si el comando falla (default: false)
  - `:interactive` - Modo interactivo para sudo (default: false)

  ## Gestión de Procesos

      # Matar procesos por nombre
      Argos.Command.kill_process("my_app")

      # Matar múltiples procesos
      results = Argos.Command.kill_processes_by_name(["app1", "app2"])

  ## Configuración

  El shell usado por defecto se configura en config.exs:

      config :argos, shell: "/bin/zsh"

  ## Struct CommandResult

  Todos los comandos (excepto raw) devuelven un %CommandResult{}:

  - `command` - Comando ejecutado
  - `args` - Argumentos del comando
  - `output` - Salida capturada
  - `exit_code` - Código de salida
  - `duration` - Duración en milisegundos
  - `success?` - true si exit_code == 0
  - `error` - Mensaje de error si lo hay
  """

  require Logger

  alias Argos.Structs.CommandResult

  @shell_timeout 30_000
  @shell Application.compile_env(:argos, :shell, "/bin/zsh")

  # ---------------- Macros (maintaining backward compatibility) ----------------
  defmacro exec_raw!(command, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote bind_quoted: [command: command, opts: opts, caller: caller] do
      opts = Keyword.put_new(opts, :stderr_to_stdout, true)
      Argos.Command.__exec__(:raw, command, opts, caller)
    end
  end

  defmacro exec!(command, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote bind_quoted: [command: command, opts: opts, caller: caller] do
      opts = Keyword.put_new(opts, :stderr_to_stdout, true)
      Argos.Command.__exec__(:normal, command, opts, caller)
    end
  end

  defmacro exec_silent!(command, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote bind_quoted: [command: command, opts: opts, caller: caller] do
      opts = Keyword.put_new(opts, :stderr_to_stdout, true)
      Argos.Command.__exec__(:silent, command, opts, caller)
    end
  end

  defmacro exec_interactive!(command, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote bind_quoted: [command: command, opts: opts, caller: caller] do
      opts = Keyword.put_new(opts, :interactive, true)
      Argos.Command.__exec__(:interactive, command, opts, caller)
    end
  end

  defmacro exec_sudo!(command, opts \\ []) do
    caller = Macro.escape(__CALLER__)

    quote bind_quoted: [command: command, opts: opts, caller: caller] do
      opts = Keyword.put_new(opts, :stderr_to_stdout, true)
      Argos.Command.__exec__(:sudo, command, opts, caller)
    end
  end

  # ---------------- Exec (maintaining original behavior for backward compatibility) ----------------
  def __exec__(:raw, command, opts, _caller) do
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

  def __exec__(:normal, command, opts, caller) do
    {halt?, opts} = Keyword.pop(opts, :halt, false)
    start_time = System.monotonic_time(:millisecond)

    {output, exit_code} = __exec__(:raw, command, opts, caller)

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

    __log_result__(command, output, exit_code, caller)
    __handle_halt__(result, halt?)

    result
  end

  def __exec__(:silent, command, opts, caller) do
    __exec__(:normal, "#{command} /dev/null 2>&1", opts, caller) |> elem(1)
  end

  def __exec__(:interactive, command, opts, caller) do
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

        result = __collect_output__(command, port, "", caller, start_time)
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
        |> __collect_output__(port, "", caller, start_time)
        |> __handle_halt__(halt?)
    end
  end

  def __exec__(:sudo, command, opts, caller) do
    # Si el comando requiere interacción, tratamos sudo como :interactive
    interactive? = Keyword.get(opts, :interactive, false)
    halt? = Keyword.get(opts, :halt, false)
    start_time = System.monotonic_time(:millisecond)

    Logger.warning("SUDO command execution attempted: #{command}")

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
      |> __collect_output__(port, "", caller, start_time)
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

  @spec halt(integer) :: no_return
  def halt(code \\ 0) do
    System.halt(code)
  end

  def __handle_halt__(%CommandResult{exit_code: code, output: msg}, true)
      when code not in [0, 1] do
    Logger.error("Error ejecutando comando: #{String.trim(msg)} (code #{code})")
    halt()
  end

  def __handle_halt__(result, _), do: result

  defp __collect_output__(command, port, acc, caller, start_time) when is_integer(start_time) do
    actual_start_time = start_time

    receive do
      {^port, {:data, data}} ->
        __collect_output__(command, port, acc <> data, caller, actual_start_time)

      {^port, {:exit_status, code}} ->
        duration = System.monotonic_time(:millisecond) - actual_start_time
        __log_result__(command, acc, code, caller)

        %CommandResult{
          command: command,
          args: [],
          output: acc,
          exit_code: code,
          duration: duration,
          success?: code == 0,
          error: nil
        }
    after
      @shell_timeout ->
        if is_port(port), do: Port.close(port)
        Logger.error("EXEC TIMEOUT -> #{String.trim(acc)}")
        __log_result__(command, acc, 1, caller)
        duration = System.monotonic_time(:millisecond) - actual_start_time

        %CommandResult{
          command: command,
          args: [],
          output: acc,
          exit_code: 1,
          duration: duration,
          success?: false,
          error: "Timeout after #{@shell_timeout}ms"
        }
    end
  end

  defp __log_result__(command, message, code, caller) do
    log_command = command |> String.split(" ") |> Enum.take(2) |> Enum.join(" ")

    log =
      "Module: #{caller.module}\\nFunction #{inspect(caller.function)} -> (#{code})\\nMessage: #{String.trim(message)}"

    case code do
      -1 ->
        Logger.info(log_command)
        Logger.debug(log)

      1 ->
        Logger.info(command)
        Logger.warning(log)

      c when c > 1 ->
        Logger.error(command)
        Logger.critical(log)

      _ ->
        :ok
    end
  end

  # ---------------- Process Response ----------------
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

  # ---------------- Utils ----------------
  def kill_process(process_name) when is_binary(process_name) do
    if String.length(process_name) > 0 and
         String.match?(process_name, ~r/^[a-zA-Z0-9_.-]+$/) do
      exec!("pgrep -f #{process_name} | head -10 | xargs kill -TERM")
    else
      Logger.error("Invalid process name: #{process_name}")

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
  Funciones auxiliares para el manejo robusto de procesos.
  """
  def kill_processes_by_name(process_names) when is_list(process_names) do
    Logger.info("Matando procesos: #{inspect(process_names)}")

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
        Logger.error("Error matando proceso #{process_name}: #{error} (#{code})")
        {:error, :kill_term_command_failed}

      {:pkill, %CommandResult{exit_code: exit_code}} when exit_code != 0 ->
        {:error, :pkill_failed}
    end
  end

  defp do_kill_term(process_name) do
    result = exec_raw!("pkill -TERM #{process_name}", timeout: 5000)
    {:kill_term, result}
  end

  defp do_pgrep(process_name) do
    Process.sleep(2000)

    result = exec_raw!("pgrep #{process_name}", timeout: 2000)
    {:pgrep, result}
  end

  defp do_pkill(_process_name, 1), do: {:pkill, %CommandResult{exit_code: 0}}

  defp do_pkill(process_name, 0) do
    result = exec_raw!("pkill -KILL #{process_name}", timeout: 5000)
    {:pkill, result}
  end
end

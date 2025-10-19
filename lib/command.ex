defmodule Argos.Command do
  @moduledoc """
  Sistema de ejecución de comandos shell - Versión sin macros.
  """

  alias Argos.Structs.CommandResult

  @shell_timeout 30_000
  @shell Application.compile_env(:argos, :shell, "/bin/zsh")

  # ---------------- API PÚBLICA SIMPLIFICADA ----------------
  @doc """
  Ejecuta un comando y devuelve un CommandResult estructurado.
  """
  def exec(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:normal, command, opts)
  end

  @doc """
  Ejecuta un comando y devuelve una tupla {output, exit_code} sin logging.
  """
  def exec_raw(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:raw, command, opts)
  end

  @doc """
  Ejecuta un comando redirigiendo salida a /dev/null.
  """
  def exec_silent(command, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)
    __exec__(:silent, command, opts)
  end

  @doc """
  Ejecuta un comando en modo interactivo.
  """
  def exec_interactive(command, opts \\ []) do
    opts = Keyword.put_new(opts, :interactive, true)
    __exec__(:interactive, command, opts)
  end

  @doc """
  Ejecuta un comando con privilegios de superusuario.
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
  Detiene el sistema con el código de salida especificado.

  Esta función no retorna - termina la VM de Erlang.
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

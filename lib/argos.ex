defmodule Argos do
  @moduledoc """
  Argos - Sistema de ejecución de comandos y orquestación de tareas.

  Librería base sin dependencias para ejecución de comandos del sistema
  y gestión de tareas asíncronas.

  ## Nivel 1B en Proyecto Ypsilon

  Argos es una librería base que NO depende de ninguna otra librería
  del proyecto. Proporciona funcionalidad pura de ejecución sin interfaces
  de usuario, devolviendo structs estructurados que pueden ser procesados
  por librerías de nivel superior.

  ## Módulos principales

  - `Argos.Command` - Ejecución de comandos del sistema
  - `Argos.AsyncTask` - Gestión de tareas asíncronas
  - `Argos.Log` - Logging estructurado
  - `Argos.Structs.CommandResult` - Resultado de comandos
  - `Argos.Structs.TaskResult` - Resultado de tareas
  """

  alias Argos.{AsyncTask, Command, Log}
  alias Argos.Structs.{CommandResult, TaskResult}

  @type command_result :: CommandResult.t()
  @type task_result :: TaskResult.t()

  # ==========================================
  # COMMAND EXECUTION API
  # ==========================================
  @spec exec_command(String.t(), [String.t()], keyword()) :: command_result()
  def exec_command(command, args \\ [], opts \\ []) do
    full_command = if args == [], do: command, else: "#{command} #{Enum.join(args, " ")}"
    Command.__exec__(:normal, full_command, opts, __ENV__)
  end

  @spec exec_raw(String.t(), keyword()) :: command_result()
  def exec_raw(command, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    {output, exit_code} = Command.__exec__(:raw, command, opts, __ENV__)
    duration = System.monotonic_time(:millisecond) - start_time

    %CommandResult{
      command: "/bin/zsh",
      args: ["-c", command],
      output: output,
      exit_code: exit_code,
      duration: duration,
      success?: exit_code == 0,
      error: nil
    }
  end

  @spec exec_sudo(String.t(), keyword()) :: command_result()
  def exec_sudo(command, opts \\ []) do
    Command.__exec__(:sudo, command, opts, __ENV__)
  end

  @spec exec_interactive(String.t(), keyword()) :: command_result()
  def exec_interactive(command, opts \\ []) do
    Command.__exec__(:interactive, command, opts, __ENV__)
  end

  # ==========================================
  # ASYNC TASK API
  # ==========================================
  def run_parallel(tasks, opts \\ []) do
    AsyncTask.run_parallel(tasks, opts)
  end

  def start_async_task(name, fun, opts \\ []) do
    AsyncTask.start(name, fun, opts)
  end

  def stop_async_task(name) do
    AsyncTask.stop(name)
  end

  def get_async_task(name) do
    AsyncTask.get(name)
  end

  # ==========================================
  # LOGGING API
  # ==========================================
  def log(level, message, metadata \\ []) do
    Log.log(level, message, metadata)
  end

  def log_command(command, exit_code, duration, output) do
    Log.log_command_execution(command, exit_code, duration, output)
  end

  def log_task(task_name, success?, duration, result) do
    Log.log_task_execution(task_name, success?, duration, result)
  end

  # ==========================================
  # UTILITY FUNCTIONS
  # ==========================================
  def kill_process(process_name) do
    Command.kill_process(process_name)
  end

  def kill_processes(process_names) do
    Command.kill_processes_by_name(process_names)
  end

  # ==========================================
  # PROCESS MANAGEMENT
  # ==========================================
  @spec halt(integer) :: no_return
  def halt(code) do
    Command.halt(code)
  end
end

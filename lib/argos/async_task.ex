defmodule Argos.AsyncTask do
  @moduledoc """
  Sistema de ejecución de tareas asíncronas sin dependencias de UI.

  Proporciona funcionalidad para ejecutar tareas en paralelo y gestionar
  su ejecución de forma estructurada, devolviendo resultados estructurados
  en lugar de manejar la presentación visual.
  """
  require Logger

  alias Argos.Command
  alias Argos.Structs.TaskResult

  @default_interval 1000

  # =========================
  # API LEGACY (compatibilidad)
  # =========================
  def start(name, fun, opts \\ []) when is_atom(name) and (is_function(fun, 0) or is_function(fun, 1)) do
    stop(name)

    task =
      case Keyword.get(opts, :cycle) do
        nil ->
          interval = Keyword.get(opts, :interval, @default_interval)
          create_task(fun, nil, interval: interval)

        list when is_list(list) ->
          create_task(fun, list, async: true)
      end

    Process.put(name, task)
    task
  end

  def create_task(fun, list, async: true) when is_function(fun, 1) do
    Task.async(fn ->
      Stream.each(Stream.cycle(list), fun)
      |> Stream.run()
    end)
  end

  def create_task(fun, list, async: true) when is_function(fun, 0) do
    Task.async(fn ->
      Stream.each(Stream.cycle(list), fn _ -> fun.() end)
      |> Stream.run()
    end)
  end

  def create_task(fun, _list, interval: interval) when is_function(fun, 1) do
    Task.async(fn -> loop_poll(fun, interval) end)
  end

  def create_task(fun, _list, interval: interval) when is_function(fun, 0) do
    Task.async(fn -> loop_poll_0(fun, interval) end)
  end

  defp loop_poll(fun, interval) when is_function(fun, 1) do
    Process.sleep(interval)
    fun.(nil)
    loop_poll(fun, interval)
  end

  defp loop_poll_0(fun, interval) when is_function(fun, 0) do
    Process.sleep(interval)
    fun.()
    loop_poll_0(fun, interval)
  end

  def stop(name) when is_atom(name) do
    case Process.get(name) do
      nil ->
        :ok

      task ->
        Task.shutdown(task, :brutal_kill)
        Process.delete(name)
        :ok
    end
  end

  def get(name), do: Process.get(name)

  # =========================
  # PARALLEL TASK EXECUTION
  # =========================
  @doc """
  Ejecuta múltiples tareas en paralelo y devuelve resultados estructurados.

  Recibe una lista de tuplas: {nombre, función/comando}
  donde:
  - nombre :: String.t() | atom() - Identificador de la tarea
  - función :: function() | String.t() - Función de Elixir o comando de shell

  ## Opciones

  - `:timeout` - Timeout total en milisegundos (default: 300_000 / 5 minutos)
  - `:max_concurrency` - Máximo número de tareas concurrentes (default: System.schedulers_online())

  ## Tipos de tareas soportadas

  - String: comando de shell que se ejecutará usando Argos.Command
  - function/0: función sin argumentos que se ejecuta directamente
  - {:command, cmd}: fuerza ejecución como comando de shell
  - {:function, fun}: fuerza ejecución como función

  ## Ejemplos

      # Comandos básicos
      tasks = [
        {"compile", "mix compile"},
        {"test", "mix test"},
        {"format_check", "mix format --check-formatted"}
      ]
      result = Argos.AsyncTask.run_parallel(tasks)

      # Funciones mixtas
      tasks = [
        {"git_status", "git status --porcelain"},
        {"connectivity", {:command, "ping -c 1 google.com"}},
        {"custom_analysis", {:function, &my_analysis_function/0}}
      ]
      result = Argos.AsyncTask.run_parallel(tasks, timeout: 60_000)

  ## Valor de retorno

  Devuelve una estructura con:
  - `results`: Lista de TaskResult structs, uno por tarea
  - `total_duration`: Duración total en milisegundos
  - `all_success?`: true si todas las tareas fueron exitosas

  """
  def run_parallel(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    start_time = System.monotonic_time(:millisecond)

    results =
      tasks
      |> Task.async_stream(
        fn {task_name, task_spec} ->
          execute_single_task(task_name, task_spec)
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, task_result} ->
          task_result

        {:exit, :timeout} ->
          TaskResult.failure("unknown", nil, 0, "Task timed out")

        {:exit, reason} ->
          TaskResult.failure("unknown", nil, 0, "Task failed: #{inspect(reason)}")
      end)

    total_duration = System.monotonic_time(:millisecond) - start_time
    all_success? = Enum.all?(results, & &1.success?)

    %{
      results: results,
      total_duration: total_duration,
      all_success?: all_success?
    }
  end

  defp execute_single_task(task_name, task_spec) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        case normalize_command(task_spec) do
          {:command, cmd} ->
            # Use Argos.Command for shell commands - using the __exec__ function directly
            command_result = Command.__exec__(:normal, cmd, [], __ENV__)

            if command_result.success? do
              command_result.output
            else
              raise "Command failed: #{command_result.output}"
            end

          {:function, fun} ->
            # Execute function directly
            fun.()
        end

      duration = System.monotonic_time(:millisecond) - start_time
      TaskResult.success(task_name, result, duration)
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        TaskResult.failure(task_name, nil, duration, Exception.message(error))
    catch
      :exit, reason ->
        duration = System.monotonic_time(:millisecond) - start_time
        TaskResult.failure(task_name, nil, duration, "Task exited: #{inspect(reason)}")
    end
  end

  # Normalize different command types into a consistent format
  defp normalize_command(command) when is_binary(command), do: {:command, command}
  defp normalize_command({:command, cmd}) when is_binary(cmd), do: {:command, cmd}
  defp normalize_command({:function, fun}) when is_function(fun), do: {:function, fun}
  defp normalize_command(fun) when is_function(fun, 0), do: {:function, fun}

  defp normalize_command(unknown) do
    Logger.warning("Unknown command type: #{inspect(unknown)}. Treating as function.")
    {:function, fn -> unknown end}
  end
end

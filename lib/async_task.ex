defmodule Argos.AsyncTask do
  @moduledoc """
  Sistema de ejecución de tareas asíncronas.
  """

  alias Argos.Command
  alias Argos.Structs.TaskResult

  @doc """
  Ejecuta múltiples tareas en paralelo y devuelve resultados estructurados.
  """
  def run_parallel(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    halt_on_failure = Keyword.get(opts, :halt_on_failure, false)

    start_time = System.monotonic_time(:millisecond)

    Argos.log(:info, "Starting parallel execution",
      task_count: length(tasks),
      max_concurrency: max_concurrency,
      timeout: timeout
    )

    results =
      tasks
      |> Task.async_stream(
        &execute_single_task/1,
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

    log_parallel_results(tasks, results, total_duration, all_success?)

    if halt_on_failure and not all_success? do
      Argos.log(:error, "Halting due to task failure", [])
      System.halt(1)
    end

    %{
      results: results,
      total_duration: total_duration,
      all_success?: all_success?
    }
  end

  @doc """
  Ejecuta una única tarea y devuelve su TaskResult.
  """
  def run_single(task_name, task_spec, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    timeout = Keyword.get(opts, :timeout, 30_000)

    Argos.log(:debug, "Starting single task", task_name: task_name)

    try do
      task_result =
        case Task.async(fn -> execute_single_task({task_name, task_spec}) end) do
          task ->
            try do
              Task.await(task, timeout)
            catch
              :exit, {:timeout, _} ->
                duration = System.monotonic_time(:millisecond) - start_time
                Task.shutdown(task, :brutal_kill)
                TaskResult.failure(task_name, nil, duration, "Task timed out after #{timeout}ms")

              :exit, reason ->
                duration = System.monotonic_time(:millisecond) - start_time
                TaskResult.failure(task_name, nil, duration, "Task exited: #{inspect(reason)}")
            end
        end

      duration = System.monotonic_time(:millisecond) - start_time

      # Si el resultado no es un TaskResult (por ejemplo, si la tarea crasheó), crear uno
      final_result =
        case task_result do
          %TaskResult{} = result ->
            # Actualizar la duración con el tiempo total (incluyendo overhead de Task)
            %{result | duration: duration}

          other ->
            TaskResult.failure(task_name, other, duration, "Unexpected result: #{inspect(other)}")
        end

      Argos.log_task(final_result)
      final_result
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        task_result = TaskResult.failure(task_name, nil, duration, Exception.message(error))
        Argos.log_task(task_result)
        task_result
    end
  end

  defp execute_single_task({task_name, task_spec}) do
    start_time = System.monotonic_time(:millisecond)

    Argos.log(:debug, "Executing task", task_name: task_name)

    try do
      result =
        case normalize_command(task_spec) do
          {:command, cmd} ->
            command_result = Command.exec(cmd, [])

            if command_result.success? do
              command_result.output
            else
              raise "Command failed: #{command_result.output}"
            end

          {:function, fun} ->
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

  defp log_parallel_results(tasks, results, total_duration, all_success?) do
    successful_count = Enum.count(results, & &1.success?)
    failed_count = length(tasks) - successful_count

    metadata = [
      total_tasks: length(tasks),
      successful_tasks: successful_count,
      failed_tasks: failed_count,
      total_duration: total_duration,
      all_success?: all_success?
    ]

    if all_success? do
      Argos.log(:success, "All parallel tasks completed successfully", metadata)
    else
      failed_tasks =
        results
        |> Enum.filter(&(!&1.success?))
        |> Enum.map(& &1.task_name)

      Argos.log(:error, "Some parallel tasks failed", metadata ++ [failed_tasks: failed_tasks])
    end
  end

  defp normalize_command(command) when is_binary(command),
    do: {:command, command}

  defp normalize_command({:command, cmd}) when is_binary(cmd),
    do: {:command, cmd}

  defp normalize_command({:function, fun}) when is_function(fun),
    do: {:function, fun}

  defp normalize_command(fun) when is_function(fun, 0),
    do: {:function, fun}

  defp normalize_command(unknown) do
    Argos.log(:warn, "Unknown command type", unknown_type: inspect(unknown))
    {:function, fn -> "Unknown task spec: #{inspect(unknown)}" end}
  end
end

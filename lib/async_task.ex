defmodule Argos.AsyncTask do
  @moduledoc """
  Provides asynchronous task execution capabilities with structured results.

  This module allows you to run both single tasks and multiple tasks in parallel.
  It includes features such as:
  - Concurrency control
  - Timeout handling
  - Error management
  - Structured result reporting
  - Automatic logging of task execution

  ## Features

  - Execute tasks in parallel with configurable concurrency
  - Support for both command-based and function-based tasks
  - Automatic task result structuring
  - Configurable timeouts and failure handling
  - Integration with Argos logging system

  ## Examples

      # Run a single task
      result = Argos.AsyncTask.run_single("my_task", fn -> "task completed" end)

      # Run multiple tasks in parallel
      tasks = [
        {"compile", "mix compile"},
        {"test", {:function, fn -> run_tests() end}},
        {"lint", "mix credo --strict"}
      ]
      results = Argos.AsyncTask.run_parallel(tasks, max_concurrency: 2)
  """

  alias Argos.Command
  alias Argos.Structs.TaskResult

  @doc """
  Executes multiple tasks in parallel and returns structured results.

  This function runs a list of tasks concurrently, managing concurrency
  and timeouts for optimal performance. Each task can be either a command
  string or a function.

  ## Parameters

    * `tasks` - List of tasks, where each task is a tuple `{task_name, task_spec}`
      - `task_name` - String or atom identifying the task
      - `task_spec` - Either a command string or `{:function, function}` tuple
    * `opts` - Keyword list of options
      - `:timeout` - Maximum time to wait for each task in milliseconds (default: 300_000)
      - `:max_concurrency` - Maximum number of concurrent tasks (default: number of schedulers)
      - `:halt_on_failure` - Whether to halt the system if any task fails (default: false)

  ## Returns

    A map containing:
    * `:results` - List of `Argos.Structs.TaskResult` structs
    * `:total_duration` - Total execution time in milliseconds
    * `:all_success?` - Boolean indicating if all tasks succeeded

  ## Examples

      # Execute multiple command tasks in parallel
      tasks = [
        {"compile", "mix compile"},
        {"test", "mix test"},
        {"format", "mix format"}
      ]
      results = Argos.AsyncTask.run_parallel(tasks, max_concurrency: 2)

      # Execute function-based tasks in parallel
      tasks = [
        {"read_file", {:function, fn -> File.read!("config.txt") end}},
        {"fetch_data", {:function, fn -> HTTPoison.get!("http://api.example.com") end}}
      ]
      results = Argos.AsyncTask.run_parallel(tasks)
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
  Executes a single task and returns its TaskResult.

  This function runs an individual task asynchronously with timeout protection
  and proper error handling. The task can be either a command string or a function.

  ## Parameters

    * `task_name` - String or atom identifying the task
    * `task_spec` - Task specification (command string or function)
      - Command string: Executes the command via `Argos.Command.exec/2`
      - Function: Executes the function directly
    * `opts` - Keyword list of options
      - `:timeout` - Maximum time to wait for the task in milliseconds (default: 30_000)

  ## Returns

    An `Argos.Structs.TaskResult` struct

  ## Examples

      # Execute a command task
      result = Argos.AsyncTask.run_single("backup", "tar -czf backup.tar.gz /home/user/docs")

      # Execute a function task
      result = Argos.AsyncTask.run_single("data_processing", fn ->
        # Some processing logic here
        Enum.map(1..100, &(&1 * 2))
      end)

      # Execute with a custom timeout
      result = Argos.AsyncTask.run_single("long_task", "sleep 10 && echo done", timeout: 15_000)
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

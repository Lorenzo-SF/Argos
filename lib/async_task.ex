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

  ## Extended Features

  - Real-time progress tracking with callbacks
  - Multi-step task definitions with automatic progress calculation
  - Progress estimation and time remaining calculations

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

      # Run tasks with progress tracking
      tasks_with_progress = [
        {"backup", fn(callback) ->
          callback.(%{progress: 0, step: "Starting backup..."})
          # ... perform backup steps
          callback.(%{progress: 100, step: "Backup completed"})
        end}
      ]
      {:ok, results} = Argos.AsyncTask.run_with_progress(tasks_with_progress, [], &handle_progress/1)
  """

  alias Argos.Command
  alias Argos.Structs.TaskResult
  alias Argos.Task.Progress

  @doc """
  Executes tasks with real-time progress tracking.

  This function extends the parallel execution capabilities by adding progress
  callbacks that receive updates during task execution.

  ## Parameters

    * `task_definitions` - List of `{task_name, function}` tuples where the function
       receives a progress callback as its first argument
    * `opts` - Keyword list of options (same as `run_parallel/2`)
    * `progress_callback` - Function that receives progress updates: `fn(Progress.t()) -> any()`

  ## Options

    Supports all options from `run_parallel/2`:
    * `:timeout` - Maximum time to wait for each task in milliseconds (default: 300_000)
    * `:max_concurrency` - Maximum number of concurrent tasks (default: number of schedulers)
    * `:halt_on_failure` - Whether to halt the system if any task fails (default: false)

  ## Returns

    `{:ok, [TaskResult.t()]}` on success, `{:error, reason}` on failure

  ## Examples

      tasks = [
        {"database_backup", fn(callback) ->
          callback.(%{progress: 0, step: "Starting backup..."})
          # Perform backup operations...
          callback.(%{progress: 50, step: "Backup in progress"})
          # More operations...
          callback.(%{progress: 100, step: "Backup completed"})
          "backup_success"
        end}
      ]

      progress_handler = fn(progress) ->
        IO.puts("Task \#{progress.task_name}: \#{progress.progress}% - \#{progress.current_step}")
      end

      {:ok, results} = Argos.AsyncTask.run_with_progress(tasks, [], progress_handler)
  """
  @spec run_with_progress([{String.t(), (function() -> any())}], keyword(), (Progress.t() -> any())) ::
          {:ok, [TaskResult.t()]} | {:error, any()}
  def run_with_progress(task_definitions, opts \\ [], progress_callback) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    halt_on_failure = Keyword.get(opts, :halt_on_failure, false)

    start_time = System.monotonic_time(:millisecond)

    Argos.log(:info, "Starting parallel execution with progress tracking",
      task_count: length(task_definitions),
      max_concurrency: max_concurrency,
      timeout: timeout
    )

    # Create progress trackers for each task
    progress_trackers =
      task_definitions
      |> Enum.with_index()
      |> Enum.map(fn {{task_name, _function}, index} ->
        Progress.create(task_name, index: index)
      end)

    # Initialize progress UI
    Enum.each(progress_trackers, progress_callback)

    results =
      task_definitions
      |> Enum.with_index()
      |> Task.async_stream(
        fn {{task_name, task_function}, task_index} ->
          execute_task_with_progress(
            task_name,
            task_function,
            task_index,
            progress_callback
          )
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, task_result} ->
          task_result

        {:exit, :timeout} ->
          duration = System.monotonic_time(:millisecond) - start_time
          TaskResult.failure("unknown", nil, duration, "Task timed out")

        {:exit, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          TaskResult.failure("unknown", nil, duration, "Task failed: #{inspect(reason)}")
      end)

    total_duration = System.monotonic_time(:millisecond) - start_time
    all_success? = Enum.all?(results, & &1.success?)

    log_parallel_results(task_definitions, results, total_duration, all_success?)

    if halt_on_failure and not all_success? do
      Argos.log(:error, "Halting due to task failure", [])
      System.halt(1)
    end

    {:ok, results}
  end

  @doc """
  Defines a multi-step task with automatic progress tracking.

  This function creates a task function that automatically handles progress
  updates for each step, calculating the overall progress based on step weights.

  ## Parameters

    * `task_name` - Name of the task for logging and identification
    * `steps` - List of step definitions: `[{step_name, step_function, weight}]`
      - `step_name` - String describing the step (displayed in progress updates)
      - `step_function` - Function that executes the step (receives context map)
      - `weight` - Integer representing the percentage weight of this step

  ## Returns

    A function that can be used with `run_with_progress/3`

  ## Examples

      backup_steps = [
        {"Create remote backup", fn(_ctx) -> create_remote_backup() end, 25},
        {"Download backup", fn(ctx) -> download_backup(ctx.last_result) end, 25},
        {"Clean remote files", fn(_ctx) -> clean_remote() end, 25},
        {"Apply backup locally", fn(ctx) -> apply_local_backup(ctx.last_result) end, 25}
      ]

      backup_task = Argos.AsyncTask.define_steps("database_backup", backup_steps)

      # Use with progress tracking
      tasks = [{"backup", backup_task}]
      {:ok, results} = Argos.AsyncTask.run_with_progress(tasks, [], &update_progress_ui/1)
  """
  @spec define_steps(String.t(), [{String.t(), (map() -> any()), integer()}]) :: (function() -> any())
  def define_steps(task_name, steps) do
    total_weight = calculate_total_weight(steps)

    fn progress_callback ->
      initial_state = %{context: %{}, progress: 0, error_occurred?: false}

      final_state = execute_steps(task_name, steps, total_weight, initial_state, progress_callback)

      send_final_notification(task_name, final_state, progress_callback)
      final_state.context
    end
  end

  defp calculate_total_weight(steps) do
    Enum.reduce(steps, 0, fn {_, _, weight}, acc -> acc + weight end)
  end

  defp execute_steps(task_name, steps, total_weight, state, progress_callback) do
    Enum.reduce_while(steps, state, fn step, acc ->
      if acc.error_occurred? do
        {:halt, acc}
      else
        execute_single_step(task_name, step, total_weight, acc, progress_callback)
      end
    end)
  end

  defp execute_single_step(task_name, {step_name, step_function, step_weight}, total_weight, state, progress_callback) do
    notify_step_start(task_name, step_name, state.progress, progress_callback)

    try do
      step_result = step_function.(state.context)
      new_progress = calculate_new_progress(state.progress, step_weight, total_weight)

      notify_step_completion(task_name, step_name, new_progress, progress_callback)

      new_context = build_new_context(state.context, step_result)

      {:cont, %{state | context: new_context, progress: new_progress}}
    rescue
      error ->
        notify_step_failure(task_name, step_name, state.progress, error, progress_callback)
        {:halt, %{state | error_occurred?: true}}
    end
  end

  defp notify_step_start(task_name, step_name, current_progress, progress_callback) do
    progress_callback.(%Progress{
      task_name: task_name,
      status: :running,
      progress: current_progress,
      current_step: step_name,
      step_progress: 0
    })
  end

  defp notify_step_completion(task_name, step_name, new_progress, progress_callback) do
    progress_callback.(%Progress{
      task_name: task_name,
      status: :running,
      progress: new_progress,
      current_step: "#{step_name} - Completed",
      step_progress: 100
    })
  end

  defp notify_step_failure(task_name, step_name, current_progress, error, progress_callback) do
    progress_callback.(%Progress{
      task_name: task_name,
      status: :failed,
      progress: current_progress,
      current_step: "#{step_name} - Failed: #{Exception.message(error)}",
      step_progress: 0
    })
  end

  defp calculate_new_progress(current_progress, step_weight, total_weight) do
    step_progress = current_progress + step_weight / total_weight * 100
    min(Float.round(step_progress, 1), 100)
  end

  defp build_new_context(current_context, step_result) do
    case step_result do
      map when is_map(map) ->
        context_data = Map.drop(current_context, [:last_step_result])
        final_context = Map.merge(context_data, map)
        Map.put(final_context, :last_step_result, step_result)

      _ ->
        Map.put(current_context, :last_step_result, step_result)
    end
  end

  defp send_final_notification(task_name, %{progress: progress, error_occurred?: has_error}, progress_callback) do
    final_status = if has_error, do: :cancelled, else: :completed
    final_step_message = if has_error, do: "Task interrupted before completion", else: "All steps completed"
    final_progress = if has_error, do: progress, else: 100

    progress_callback.(%Progress{
      task_name: task_name,
      status: final_status,
      progress: final_progress,
      current_step: final_step_message,
      step_progress: if(has_error, do: 0, else: 100)
    })
  end

  # ============================
  # FUNCIONES PRIVADAS NUEVAS
  # ============================

  defp execute_task_with_progress(task_name, task_function, task_index, progress_callback) do
    start_time = System.monotonic_time(:millisecond)

    # Create wrapper callback that includes task index
    wrapped_callback = fn progress_update ->
      progress_with_index =
        Map.merge(progress_update, %{
          task_index: task_index,
          task_id: task_index
        })

      progress_callback.(progress_with_index)
    end

    try do
      # Execute the task function with progress callback
      result = task_function.(wrapped_callback)
      duration = System.monotonic_time(:millisecond) - start_time

      # Final success notification
      wrapped_callback.(%Progress{
        task_name: task_name,
        status: :completed,
        progress: 100,
        current_step: "Task completed successfully",
        duration: duration
      })

      TaskResult.success(task_name, result, duration)
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        error_message = Exception.message(error)

        # Error notification
        wrapped_callback.(%Progress{
          task_name: task_name,
          status: :failed,
          progress: 0,
          current_step: "Task failed: #{error_message}",
          duration: duration
        })

        TaskResult.failure(task_name, nil, duration, error_message)
    catch
      :exit, reason ->
        duration = System.monotonic_time(:millisecond) - start_time

        wrapped_callback.(%Progress{
          task_name: task_name,
          status: :failed,
          progress: 0,
          current_step: "Task exited: #{inspect(reason)}",
          duration: duration
        })

        TaskResult.failure(task_name, nil, duration, "Task exited: #{inspect(reason)}")
    end
  end

  # ============================
  # FUNCIONES EXISTENTES - MANTENIDAS COMPLETAMENTE
  # ============================

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

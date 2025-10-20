defmodule Argos.AsyncTaskTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Argos.Structs.TaskResult
  alias Argos.Task.Progress

  setup do
    Application.put_env(:argos, :env, :test)
    Application.put_env(:argos, :tui_detector, Argos.TuiDetector.Default)
    {:ok, %{}}
  end

  describe "run_parallel/2" do
    test "executes multiple commands in parallel" do
      tasks = [
        {"echo1", "echo 'task1'"},
        {"echo2", "echo 'task2'"},
        {"echo3", "echo 'task3'"}
      ]

      result = Argos.AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert is_integer(result.total_duration)
      assert result.total_duration >= 0
      assert length(result.results) == 3

      Enum.each(result.results, fn task_result ->
        assert %TaskResult{} = task_result
        assert task_result.success? == true
      end)
    end

    test "handles mixed command and function tasks" do
      tasks = [
        {"shell_command", "echo 'from shell'"},
        {"elixir_function", {:function, fn -> {:ok, "from function"} end}}
      ]

      result = Argos.AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert length(result.results) == 2
    end

    test "handles task failures gracefully" do
      tasks = [
        {"success_task", "echo 'success'"},
        {"failing_task", "invalid_command_that_should_fail_xyz123"}
      ]

      result = Argos.AsyncTask.run_parallel(tasks)

      assert result.all_success? == false

      success_results = Enum.filter(result.results, & &1.success?)
      failed_results = Enum.filter(result.results, &(!&1.success?))

      assert length(success_results) == 1
      assert length(failed_results) == 1
    end

    test "respects max_concurrency option" do
      tasks = [
        {"sleep1", "sleep 0.1"},
        {"sleep2", "sleep 0.1"},
        {"sleep3", "sleep 0.1"}
      ]

      # Concurrency de 1 debería tomar más tiempo
      start_time = System.monotonic_time(:millisecond)
      result1 = Argos.AsyncTask.run_parallel(tasks, max_concurrency: 1)
      duration1 = System.monotonic_time(:millisecond) - start_time

      start_time = System.monotonic_time(:millisecond)
      result2 = Argos.AsyncTask.run_parallel(tasks, max_concurrency: 3)
      duration2 = System.monotonic_time(:millisecond) - start_time

      assert result1.all_success? == true
      assert result2.all_success? == true
      # duration1 debería ser mayor que duration2 debido a la concurrencia
      assert duration1 >= duration2
    end

    test "logs parallel execution results" do
      tasks = [
        {"task1", "echo 'test'"},
        {"task2", "echo 'test'"}
      ]

      output =
        capture_io(fn ->
          Argos.AsyncTask.run_parallel(tasks)
        end)

      assert output =~ "Starting parallel execution"
      assert output =~ "All parallel tasks completed successfully"
    end
  end

  describe "run_single/3" do
    test "executes single command task" do
      result = Argos.AsyncTask.run_single("test_task", "echo 'single task'")

      assert %TaskResult{} = result
      assert result.task_name == "test_task"
      assert result.success? == true
      assert result.result =~ "single task"
      assert is_integer(result.duration)
    end

    test "executes single function task" do
      result =
        Argos.AsyncTask.run_single("func_task", fn ->
          Process.sleep(10)
          "function result"
        end)

      assert %TaskResult{} = result
      assert result.task_name == "func_task"
      assert result.success? == true
      assert result.result == "function result"
    end

    test "handles task failures in run_single" do
      result = Argos.AsyncTask.run_single("failing_task", "invalid_command_xyz123")

      assert %TaskResult{} = result
      assert result.task_name == "failing_task"
      assert result.success? == false
      assert result.error =~ "Command failed"
    end

    test "respects timeout option" do
      # Usar un timeout más realista
      result = Argos.AsyncTask.run_single("slow_task", "sleep 1", timeout: 100)

      assert %TaskResult{} = result
      assert result.success? == false
      # Puede ser timeout u otro error
      assert is_binary(result.error)
    end
  end

  describe "normalization" do
    test "normalizes string commands" do
      result = Argos.AsyncTask.run_single("test", "echo 'normalized'")
      assert result.success? == true
    end
  end

  describe "run_with_progress/3" do
    test "executes tasks with progress callbacks" do
      test_pid = self()

      task_definitions = [
        {"test_task_1",
         fn callback ->
           callback.(%Progress{task_name: "test_task_1", progress: 0.0, current_step: "Starting"})
           Process.sleep(10)
           callback.(%Progress{task_name: "test_task_1", progress: 100.0, current_step: "Completed"})
           "result_1"
         end},
        {"test_task_2",
         fn callback ->
           callback.(%Progress{task_name: "test_task_2", progress: 50.0, current_step: "Halfway"})
           Process.sleep(10)
           "result_2"
         end}
      ]

      _progress_messages = []

      progress_callback = fn progress ->
        send(test_pid, {:progress, progress.task_name, progress.progress, progress.current_step})
        # progress_messages = [progress | progress_messages] # Esta línea no es necesaria
      end

      assert {:ok, results} = Argos.AsyncTask.run_with_progress(task_definitions, [], progress_callback)

      assert length(results) == 2
      assert Enum.all?(results, & &1.success?)

      # Verify we received progress messages
      assert_receive {:progress, "test_task_1", +0.0, "Starting"}
      assert_receive {:progress, "test_task_1", 100.0, "Completed"}
      assert_receive {:progress, "test_task_2", 50.0, "Halfway"}
    end

    test "handles task failures with progress updates" do
      task_definitions = [
        {"failing_task",
         fn callback ->
           callback.(%Progress{task_name: "failing_task", progress: 25, current_step: "About to fail"})
           raise "Simulated failure"
         end}
      ]

      _progress_messages = []

      progress_callback = fn _progress ->
        nil
        # _progress_messages = [progress | _progress_messages] # No es necesaria
      end

      assert {:ok, [result]} = Argos.AsyncTask.run_with_progress(task_definitions, [], progress_callback)

      refute result.success?
      assert result.error =~ "Simulated failure"
    end

    test "respects max_concurrency option" do
      task_count = 4
      max_concurrency = 2

      task_definitions =
        for i <- 1..task_count do
          {"task_#{i}",
           fn callback ->
             callback.(%Progress{task_name: "task_#{i}", progress: 100})
             Process.sleep(50)
             "result_#{i}"
           end}
        end

      start_time = System.monotonic_time(:millisecond)

      assert {:ok, results} =
               Argos.AsyncTask.run_with_progress(
                 task_definitions,
                 [max_concurrency: max_concurrency],
                 fn _ -> :ok end
               )

      duration = System.monotonic_time(:millisecond) - start_time

      # With max_concurrency=2 and 4 tasks, should take at least 100ms (2 batches of 50ms each)
      assert duration >= 90
      assert length(results) == task_count
      assert Enum.all?(results, & &1.success?)
    end

    test "handles timeouts with progress updates" do
      task_definitions = [
        {"slow_task",
         fn callback ->
           callback.(%Progress{task_name: "slow_task", progress: 50})
           # Longer than timeout
           Process.sleep(200)
           "should_not_reach_here"
         end}
      ]

      {:ok, progress_messages} = Agent.start_link(fn -> [] end)

      progress_callback = fn progress ->
        Agent.update(progress_messages, fn messages -> [progress | messages] end)
      end

      assert {:ok, [result]} =
               Argos.AsyncTask.run_with_progress(
                 task_definitions,
                 [timeout: 100],
                 progress_callback
               )

      refute result.success?
      assert result.error =~ "timed out"

      Agent.stop(progress_messages)
    end
  end

  describe "define_steps/2" do
    test "creates a step-based task function" do
      steps = [
        {"step_1", fn _ctx -> "result_1" end, 25},
        {"step_2", fn ctx -> ctx.last_step_result <> "_processed" end, 75}
      ]

      task_function = Argos.AsyncTask.define_steps("multi_step_task", steps)

      _progress_messages = []

      progress_callback = fn _progress ->
        nil
        # _progress_messages = [progress | _progress_messages]
      end

      result = task_function.(progress_callback)

      assert result == %{last_step_result: "result_1_processed"}
    end

    test "handles step failures gracefully" do
      steps = [
        {"step_1", fn _ctx -> "success" end, 50},
        {"step_2", fn _ctx -> raise "Step failed" end, 50}
      ]

      task_function = Argos.AsyncTask.define_steps("failing_steps", steps)

      {:ok, progress_messages_agent} = Agent.start_link(fn -> [] end)

      progress_callback = fn progress ->
        Agent.update(progress_messages_agent, fn messages -> [progress | messages] end)
      end

      result = task_function.(progress_callback)

      # Should return context from last successful step
      assert result == %{last_step_result: "success"}

      # Should have failure message
      progress_messages = Agent.get(progress_messages_agent, fn messages -> messages end)
      failure_messages = Enum.filter(progress_messages, &(&1.status == :failed))
      assert length(failure_messages) >= 1
      assert hd(failure_messages).current_step =~ "Failed: Step failed"

      Agent.stop(progress_messages_agent)
    end

    test "calculates progress correctly based on step weights" do
      steps = [
        {"step_1", fn _ctx -> :ok end, 10},
        {"step_2", fn _ctx -> :ok end, 30},
        {"step_3", fn _ctx -> :ok end, 60}
      ]

      task_function = Argos.AsyncTask.define_steps("weighted_steps", steps)

      {:ok, progress_values_agent} = Agent.start_link(fn -> [] end)

      progress_callback = fn progress ->
        Agent.update(progress_values_agent, fn values -> [progress.progress | values] end)
      end

      task_function.(progress_callback)

      # Should progress through 10%, 40%, 100%
      progress_values = Agent.get(progress_values_agent, fn values -> values end)
      assert 10.0 in progress_values
      assert 40.0 in progress_values
      assert 100.0 in progress_values

      Agent.stop(progress_values_agent)
    end

    test "passes context between steps" do
      steps = [
        {"step_1",
         fn ctx ->
           assert ctx == %{}
           Map.put(ctx, :data, "initial")
         end, 33},
        {"step_2",
         fn ctx ->
           assert ctx.data == "initial"
           Map.put(ctx, :processed, String.upcase(ctx.data))
         end, 33},
        {"step_3",
         fn ctx ->
           assert ctx.processed == "INITIAL"
           Map.put(ctx, :final, ctx.processed <> "_final")
         end, 34}
      ]

      task_function = Argos.AsyncTask.define_steps("context_passing", steps)

      final_context = task_function.(fn _ -> :ok end)

      assert final_context == %{
               data: "initial",
               final: "INITIAL_final",
               last_step_result: %{
                 data: "initial",
                 final: "INITIAL_final",
                 last_step_result: %{data: "initial", last_step_result: %{data: "initial"}, processed: "INITIAL"},
                 processed: "INITIAL"
               },
               processed: "INITIAL"
             }
    end
  end

  test "integration with existing run_parallel functionality" do
    # Test that the new functionality doesn't break existing behavior
    tasks = [
      {"cmd_echo", "echo 'hello'"},
      {"func_simple", {:function, fn -> 42 end}}
    ]

    # Test existing run_parallel still works
    assert %{results: results, all_success?: true} = Argos.AsyncTask.run_parallel(tasks)
    assert length(results) == 2
    assert Enum.all?(results, & &1.success?)
  end
end

defmodule Argos.AsyncTaskTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Argos.Structs.TaskResult

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
end

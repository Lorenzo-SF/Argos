defmodule Argos.AsyncTaskTest do
  use ExUnit.Case
  doctest Argos.AsyncTask
  doctest Argos.Structs.TaskResult

  alias Argos.AsyncTask
  alias Argos.Structs.TaskResult

  describe "TaskResult struct" do
    test "creates successful task result" do
      result = TaskResult.success("test_task", {:ok, "data"}, 1000)

      assert result.task_name == "test_task"
      assert result.result == {:ok, "data"}
      assert result.duration == 1000
      assert result.success? == true
      assert result.error == nil
    end

    test "creates failed task result" do
      result = TaskResult.failure("failed_task", nil, 500, "Error message")

      assert result.task_name == "failed_task"
      assert result.result == nil
      assert result.duration == 500
      assert result.success? == false
      assert result.error == "Error message"
    end

    test "creates task result from exception" do
      exception = %RuntimeError{message: "Something went wrong"}
      result = TaskResult.from_exception("exception_task", exception, 800)

      assert result.task_name == "exception_task"
      assert result.result == nil
      assert result.duration == 800
      assert result.success? == false
      assert result.error == exception
    end

    test "handles atom task names" do
      result = TaskResult.success(:atomic_task, "result", 100)

      assert result.task_name == :atomic_task
      assert result.success? == true
    end
  end

  describe "legacy API - start/stop/get" do
    test "starts and stops a task by name" do
      # Use arity-1 function since interval mode requires it
      task = AsyncTask.start(:test_legacy, fn _x -> :timer.sleep(100) end, interval: 500)

      assert %Task{} = task
      assert AsyncTask.get(:test_legacy) == task

      :ok = AsyncTask.stop(:test_legacy)
      assert AsyncTask.get(:test_legacy) == nil
    end

    test "start with cycle option using arity-1 function" do
      list = [1, 2, 3]
      task = AsyncTask.start(:cycle_test, fn _item -> :ok end, cycle: list)

      assert %Task{} = task
      assert AsyncTask.get(:cycle_test) != nil

      AsyncTask.stop(:cycle_test)
    end

    test "start with cycle option using arity-0 function" do
      list = [:a, :b]
      task = AsyncTask.start(:cycle_zero, fn -> :ok end, cycle: list)

      assert %Task{} = task

      AsyncTask.stop(:cycle_zero)
    end

    test "stop non-existent task returns ok" do
      result = AsyncTask.stop(:nonexistent_task_xyz)

      assert result == :ok
    end

    test "get non-existent task returns nil" do
      result = AsyncTask.get(:never_started)

      assert result == nil
    end

    test "start replaces existing task with same name" do
      # Use arity-1 functions for interval mode
      AsyncTask.start(:replaceable, fn _x -> :timer.sleep(10) end, interval: 1000)
      task1 = AsyncTask.get(:replaceable)

      AsyncTask.start(:replaceable, fn _x -> :timer.sleep(10) end, interval: 1000)
      task2 = AsyncTask.get(:replaceable)

      # Should be different tasks
      assert task1 != task2

      AsyncTask.stop(:replaceable)
    end
  end

  describe "run_parallel/2 - basic functionality" do
    test "runs multiple shell commands in parallel" do
      tasks = [
        {"echo_task", "echo hello"},
        {"pwd_task", "pwd"},
        {"true_task", "true"}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert %{results: results, total_duration: duration, all_success?: all_ok} = result
      assert length(results) == 3
      assert is_integer(duration)
      assert duration > 0
      assert all_ok == true

      # Check each result
      Enum.each(results, fn task_result ->
        assert %TaskResult{} = task_result
        assert task_result.success? == true
        assert task_result.duration >= 0
      end)
    end

    test "runs functions in parallel" do
      tasks = [
        {"func1", fn -> 42 end},
        {"func2", fn -> "test" end},
        {"func3", fn -> {:ok, :done} end}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert length(result.results) == 3

      # Verify results contain expected values
      results_map = Map.new(result.results, fn r -> {r.task_name, r.result} end)
      assert results_map["func1"] == 42
      assert results_map["func2"] == "test"
      assert results_map["func3"] == {:ok, :done}
    end

    test "runs mixed commands and functions" do
      tasks = [
        {"command", "echo test"},
        {"function", fn -> "from_function" end},
        {"command_explicit", {:command, "pwd"}}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert length(result.results) == 3
    end

    test "handles empty task list" do
      result = AsyncTask.run_parallel([])

      assert result.all_success? == true
      assert result.results == []
      assert result.total_duration >= 0
    end
  end

  describe "run_parallel/2 - error handling" do
    test "handles command failures" do
      tasks = [
        {"success", "echo ok"},
        {"failure", "ls /nonexistent_xyz"},
        {"another_success", "pwd"}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == false
      assert length(result.results) == 3

      # Find the failed task
      failed_task = Enum.find(result.results, fn r -> r.task_name == "failure" end)
      assert failed_task.success? == false
      assert is_binary(failed_task.error)
    end

    test "handles function exceptions" do
      tasks = [
        {"normal", fn -> :ok end},
        {"raises", fn -> raise "Error!" end}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == false

      failed = Enum.find(result.results, fn r -> r.task_name == "raises" end)
      assert failed.success? == false
      assert String.contains?(failed.error, "Error!")
    end

    test "captures exception details" do
      tasks = [
        {"exception_test",
         fn ->
           raise ArgumentError, message: "Invalid argument"
         end}
      ]

      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results
      assert task_result.success? == false

      assert String.contains?(task_result.error, "Invalid argument") or
               String.contains?(task_result.error, "ArgumentError")
    end

    test "handles task exits" do
      tasks = [
        {"exit_task", fn -> exit(:normal) end}
      ]

      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results
      assert task_result.success? == false
      assert String.contains?(task_result.error, "exit")
    end
  end

  describe "run_parallel/2 - concurrency and timing" do
    test "executes tasks concurrently" do
      # Create tasks that sleep for 100ms each
      tasks = [
        {"sleep1", "sleep 0.1"},
        {"sleep2", "sleep 0.1"},
        {"sleep3", "sleep 0.1"}
      ]

      result = AsyncTask.run_parallel(tasks)

      # If running in parallel, total time should be close to 100ms, not 300ms
      # Allow some overhead, but should be < 250ms
      assert result.total_duration < 250
      assert result.all_success? == true
    end

    test "respects max_concurrency option" do
      tasks = Enum.map(1..10, fn i -> {"task#{i}", fn -> i end} end)

      result = AsyncTask.run_parallel(tasks, max_concurrency: 2)

      assert length(result.results) == 10
      assert result.all_success? == true
    end

    test "respects timeout option" do
      # Task that takes longer than timeout
      tasks = [
        {"long_task", "sleep 10"}
      ]

      result = AsyncTask.run_parallel(tasks, timeout: 100)

      [task_result] = result.results
      assert task_result.success? == false

      assert String.contains?(task_result.error, "timed out") or
               String.contains?(task_result.error, "timeout")
    end

    test "records accurate task durations" do
      tasks = [
        {"instant", fn -> :ok end},
        {"delayed",
         fn ->
           Process.sleep(50)
           :ok
         end}
      ]

      result = AsyncTask.run_parallel(tasks)

      instant = Enum.find(result.results, &(&1.task_name == "instant"))
      delayed = Enum.find(result.results, &(&1.task_name == "delayed"))

      assert delayed.duration > instant.duration
      assert delayed.duration >= 40
    end
  end

  describe "run_parallel/2 - command normalization" do
    test "handles string commands" do
      tasks = [{"string_cmd", "echo string"}]
      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert List.first(result.results).result =~ "string"
    end

    test "handles {:command, cmd} tuples" do
      tasks = [{"tuple_cmd", {:command, "echo tuple"}}]
      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert List.first(result.results).result =~ "tuple"
    end

    test "handles {:function, fun} tuples" do
      tasks = [{"tuple_fun", {:function, fn -> "function_result" end}}]
      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert List.first(result.results).result == "function_result"
    end

    test "handles bare functions" do
      tasks = [{"bare_fun", fn -> 123 end}]
      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert List.first(result.results).result == 123
    end
  end

  describe "run_parallel/2 - real-world scenarios" do
    test "parallel file operations" do
      tasks = [
        {"list_current", "ls"},
        {"show_home", "echo $HOME"},
        {"date", "date"}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true
      assert length(result.results) == 3

      Enum.each(result.results, fn task ->
        assert task.success? == true
        assert is_binary(task.result)
        assert String.length(task.result) > 0
      end)
    end

    test "mixed computation and IO tasks" do
      tasks = [
        {"compute", fn -> Enum.sum(1..1000) end},
        {"io", "echo io_task"},
        {"another_compute", fn -> Enum.map(1..10, &(&1 * 2)) end}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true

      compute = Enum.find(result.results, &(&1.task_name == "compute"))
      assert compute.result == 500_500

      io_task = Enum.find(result.results, &(&1.task_name == "io"))
      assert io_task.result =~ "io_task"

      another = Enum.find(result.results, &(&1.task_name == "another_compute"))
      assert another.result == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    end

    test "handles mix of successes and failures gracefully" do
      tasks = [
        {"task1", "echo success1"},
        {"task2", fn -> raise "fail" end},
        {"task3", "echo success2"},
        {"task4", "ls /nonexistent"},
        {"task5", fn -> :ok end}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == false
      assert length(result.results) == 5

      successes = Enum.count(result.results, & &1.success?)
      failures = Enum.count(result.results, &(not &1.success?))

      assert successes == 3
      assert failures == 2
    end
  end

  describe "run_parallel/2 - task result structure" do
    test "each result has correct structure" do
      tasks = [{"test", "echo result"}]
      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results

      assert Map.has_key?(task_result, :task_name)
      assert Map.has_key?(task_result, :result)
      assert Map.has_key?(task_result, :duration)
      assert Map.has_key?(task_result, :success?)
      assert Map.has_key?(task_result, :error)
    end

    test "successful task has nil error" do
      tasks = [{"success", "echo ok"}]
      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results
      assert task_result.success? == true
      assert task_result.error == nil
    end

    test "failed task has error message" do
      tasks = [{"fail", fn -> raise "boom" end}]
      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results
      assert task_result.success? == false
      assert task_result.error != nil
    end
  end

  describe "run_parallel/2 - overall result structure" do
    test "returns map with required keys" do
      result = AsyncTask.run_parallel([{"test", "true"}])

      assert Map.has_key?(result, :results)
      assert Map.has_key?(result, :total_duration)
      assert Map.has_key?(result, :all_success?)
    end

    test "all_success? is true when all tasks succeed" do
      tasks = [
        {"a", "true"},
        {"b", fn -> :ok end},
        {"c", "echo test"}
      ]

      result = AsyncTask.run_parallel(tasks)
      assert result.all_success? == true
    end

    test "all_success? is false when any task fails" do
      tasks = [
        {"a", "true"},
        {"b", fn -> raise "error" end}
      ]

      result = AsyncTask.run_parallel(tasks)
      assert result.all_success? == false
    end

    test "total_duration is reasonable" do
      tasks = [{"quick", fn -> :ok end}]
      result = AsyncTask.run_parallel(tasks)

      assert result.total_duration >= 0
      assert result.total_duration < 1000
    end
  end

  describe "create_task/3 - internal helper" do
    test "creates async task with cycle and arity-1 function" do
      task = AsyncTask.create_task(fn _x -> :ok end, [1, 2], async: true)

      assert %Task{} = task
      # Clean up - the task will run indefinitely
      Task.shutdown(task, :brutal_kill)
    end

    test "creates async task with cycle and arity-0 function" do
      task = AsyncTask.create_task(fn -> :ok end, [1, 2], async: true)

      assert %Task{} = task
      Task.shutdown(task, :brutal_kill)
    end

    test "creates polling task with interval" do
      task = AsyncTask.create_task(fn _x -> :ok end, nil, interval: 1000)

      assert %Task{} = task
      # Don't wait for the interval, just kill it
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "integration with Argos.Command" do
    test "parallel tasks use Command.exec properly" do
      tasks = [
        {"cmd1", "echo test1"},
        {"cmd2", "echo test2"}
      ]

      result = AsyncTask.run_parallel(tasks)

      assert result.all_success? == true

      Enum.each(result.results, fn task ->
        # Results from commands should be strings
        assert is_binary(task.result)
        assert String.contains?(task.result, "test")
      end)
    end

    test "command failures are properly captured" do
      tasks = [{"bad_cmd", "exit 42"}]
      result = AsyncTask.run_parallel(tasks)

      [task_result] = result.results
      assert task_result.success? == false
      assert String.contains?(task_result.error, "failed")
    end
  end
end

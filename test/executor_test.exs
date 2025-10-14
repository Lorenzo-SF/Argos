defmodule ArgosTest do
  use ExUnit.Case, async: true
  doctest Argos

  alias Argos.Structs.{CommandResult, TaskResult}

  describe "command execution" do
    test "exec_command/2 executes simple commands successfully" do
      result = Argos.exec_command("echo", ["hello world"])

      assert %CommandResult{} = result
      assert result.success? == true
      assert result.exit_code == 0
      assert String.contains?(result.output, "hello world")
      assert is_integer(result.duration)
      assert result.duration >= 0
    end

    test "exec_raw/1 executes commands without logging" do
      result = Argos.exec_raw("pwd")

      assert %CommandResult{} = result
      assert result.success? == true
      assert result.exit_code == 0
      assert is_binary(result.output)
      assert is_integer(result.duration)
    end

    test "exec_command/2 handles failing commands" do
      result = Argos.exec_command("false")

      assert %CommandResult{} = result
      assert result.success? == false
      assert result.exit_code == 1
      assert is_integer(result.duration)
    end

    test "exec_command/2 handles non-existent commands" do
      result = Argos.exec_command("nonexistentcommand12345")

      assert %CommandResult{} = result
      assert result.success? == false
      assert result.exit_code != 0
    end
  end

  describe "async task execution" do
    test "run_parallel/2 executes simple tasks successfully" do
      tasks = [
        {"echo_test", "echo hello"},
        {"pwd_test", "pwd"}
      ]

      result = Argos.run_parallel(tasks)

      assert is_map(result)
      assert Map.has_key?(result, :results)
      assert Map.has_key?(result, :total_duration)
      assert Map.has_key?(result, :all_success?)

      assert length(result.results) == 2
      assert is_integer(result.total_duration)
      assert result.total_duration >= 0

      # Check that all tasks succeeded
      assert Enum.all?(result.results, fn task_result ->
               %TaskResult{} = task_result
               task_result.success?
             end)

      assert result.all_success? == true
    end

    test "run_parallel/2 executes function tasks" do
      tasks = [
        {"math_task", {:function, fn -> 2 + 2 end}},
        {"string_task", {:function, fn -> "test result" end}}
      ]

      result = Argos.run_parallel(tasks)

      assert length(result.results) == 2
      assert result.all_success? == true

      # Verify task results
      math_result = Enum.find(result.results, &(&1.task_name == "math_task"))
      string_result = Enum.find(result.results, &(&1.task_name == "string_task"))

      assert math_result.result == 4
      assert string_result.result == "test result"
    end

    test "run_parallel/2 handles mixed success and failure" do
      tasks = [
        {"success_task", "echo success"},
        {"failure_task", "false"}
      ]

      result = Argos.run_parallel(tasks)

      assert length(result.results) == 2
      assert result.all_success? == false

      # Check individual results
      success_task = Enum.find(result.results, &(&1.task_name == "success_task"))
      failure_task = Enum.find(result.results, &(&1.task_name == "failure_task"))

      assert success_task.success? == true
      assert failure_task.success? == false
    end

    test "run_parallel/2 with max_concurrency option" do
      tasks = [
        {"task1", "echo 1"},
        {"task2", "echo 2"},
        {"task3", "echo 3"}
      ]

      result = Argos.run_parallel(tasks, max_concurrency: 1)

      assert length(result.results) == 3
      assert result.all_success? == true
    end
  end

  describe "logging functionality" do
    test "log/3 accepts different log levels" do
      assert :ok = Argos.log(:info, "test message")
      assert :ok = Argos.log(:warning, "test warning")
      assert :ok = Argos.log(:error, "test error")
      assert :ok = Argos.log(:debug, "test debug")
    end

    test "log/3 accepts metadata" do
      metadata = [task_id: 123, duration: 1500, success: true]
      assert :ok = Argos.log(:info, "test with metadata", metadata)
    end

    test "log_command/4 logs command execution" do
      assert :ok = Argos.log_command("ls -la", 0, 250, "total 8\n")
      assert :ok = Argos.log_command("false", 1, 100, "")
    end

    test "log_task/4 logs task execution" do
      assert :ok = Argos.log_task("backup", true, 5000, "completed")
      assert :ok = Argos.log_task("sync", false, 1000, {:error, "network timeout"})
    end
  end

  describe "process management" do
    test "kill_process/1 handles invalid process names" do
      result = Argos.kill_process("invalid process name with spaces")

      assert %CommandResult{} = result
      assert result.success? == false
      assert String.contains?(result.output, "Invalid process name")
    end

    test "kill_process/1 handles non-binary input" do
      result = Argos.kill_process(123)

      assert %CommandResult{} = result
      assert result.success? == false
      assert String.contains?(result.output, "Process name must be a string")
    end
  end

  describe "struct creation helpers" do
    test "CommandResult.success/4 creates successful result" do
      result = CommandResult.success("ls", ["-la"], "output", 100)

      assert result.command == "ls"
      assert result.args == ["-la"]
      assert result.output == "output"
      assert result.exit_code == 0
      assert result.duration == 100
      assert result.success? == true
      assert result.error == nil
    end

    test "CommandResult.failure/6 creates failure result" do
      result = CommandResult.failure("ls", ["-invalid"], "error", 1, 50, "invalid option")

      assert result.command == "ls"
      assert result.args == ["-invalid"]
      assert result.output == "error"
      assert result.exit_code == 1
      assert result.duration == 50
      assert result.success? == false
      assert result.error == "invalid option"
    end

    test "TaskResult.success/3 creates successful task result" do
      result = TaskResult.success("test_task", "result", 200)

      assert result.task_name == "test_task"
      assert result.result == "result"
      assert result.duration == 200
      assert result.success? == true
      assert result.error == nil
    end

    test "TaskResult.failure/4 creates failure task result" do
      result = TaskResult.failure("test_task", nil, 150, "error occurred")

      assert result.task_name == "test_task"
      assert result.result == nil
      assert result.duration == 150
      assert result.success? == false
      assert result.error == "error occurred"
    end
  end
end

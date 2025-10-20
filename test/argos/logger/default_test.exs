defmodule Argos.Logger.DefaultTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Argos.Structs.{CommandResult, TaskResult}

  setup do
    Application.put_env(:argos, :tui_detector, Argos.TuiDetector.Default)
    {:ok, %{}}
  end

  describe "log/3" do
    test "logs info messages with metadata" do
      output =
        capture_io(fn ->
          Argos.Logger.Default.log(:info, "test message",
            module: MyApp.Test,
            function: "test_function/0",
            file: "test.ex",
            line: 42
          )
        end)

      assert output =~ "test message"
      assert output =~ "MyApp.Test.test_function/0"
      assert output =~ "[i]"
    end

    test "handles binary messages" do
      output =
        capture_io(fn ->
          Argos.Logger.Default.log(:debug, "binary message", [])
        end)

      assert output =~ "binary message"
      assert output =~ "[d]"
    end

    test "handles non-binary messages with inspect" do
      output =
        capture_io(fn ->
          Argos.Logger.Default.log(:warn, %{data: "test"}, [])
        end)

      assert output =~ "%{data: \"test\"}"
      assert output =~ "[!]"
    end

    test "applies correct colors for different levels" do
      output =
        capture_io(fn ->
          Argos.Logger.Default.log(:success, "success message", [])
        end)

      assert output =~ "success message"
      assert output =~ "[✓]"
    end
  end

  describe "log_command/1" do
    test "logs successful command" do
      result = %CommandResult{
        command: "ls -la",
        output: "total 8\ndrwxr-xr-x",
        exit_code: 0,
        duration: 150,
        success?: true
      }

      output =
        capture_io(fn ->
          Argos.Logger.Default.log_command(result)
        end)

      assert output =~ "Command: ls -la"
      assert output =~ "[i]"
    end

    test "logs failed command" do
      result = %CommandResult{
        command: "invalid_cmd",
        output: "command not found",
        exit_code: 127,
        duration: 50,
        success?: false
      }

      output =
        capture_io(fn ->
          Argos.Logger.Default.log_command(result)
        end)

      assert output =~ "Command: invalid_cmd"
      assert output =~ "[X]"
    end
  end

  describe "log_task/1" do
    test "logs successful task" do
      result = %TaskResult{
        task_name: "database_backup",
        result: "backup_completed",
        duration: 2000,
        success?: true
      }

      output =
        capture_io(fn ->
          Argos.Logger.Default.log_task(result)
        end)

      assert output =~ "Task: database_backup"
      assert output =~ "[✓]"
    end

    test "logs failed task" do
      result = %TaskResult{
        task_name: "database_backup",
        result: nil,
        duration: 500,
        success?: false,
        error: "Connection timeout"
      }

      output =
        capture_io(fn ->
          Argos.Logger.Default.log_task(result)
        end)

      assert output =~ "Task: database_backup"
      assert output =~ "[X]"
    end
  end
end

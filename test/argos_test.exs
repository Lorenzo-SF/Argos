defmodule ArgosTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Argos.Structs.{CommandResult, TaskResult}

  setup do
    Application.put_env(:argos, :env, :test)
    Application.put_env(:argos, :tui_detector, Argos.TuiDetector.Default)
    {:ok, %{}}
  end

  describe "log/3" do
    test "delegates to configured logger" do
      output =
        capture_io(fn ->
          Argos.log(:info, "test message", module: Test, function: "test/0")
        end)

      # Usar regex para ignorar colores ANSI y timestamp
      assert output =~ "test message"
      assert output =~ "Test.test/0"
    end
  end

  describe "log_command/1" do
    test "logs command result" do
      result = %CommandResult{
        command: "test_cmd",
        exit_code: 0,
        duration: 100,
        success?: true
      }

      output =
        capture_io(fn ->
          Argos.log_command(result)
        end)

      assert output =~ "Command: test_cmd"
    end
  end

  describe "log_task/1" do
    test "logs task result" do
      result = %TaskResult{
        task_name: "test_task",
        duration: 200,
        success?: true
      }

      output =
        capture_io(fn ->
          Argos.log_task(result)
        end)

      assert output =~ "Task: test_task"
    end
  end

  describe "tui_mode?/0" do
    test "delegates to TuiDetector" do
      assert Argos.tui_mode?() == false
    end
  end

  describe "current_logger/0" do
    test "returns configured logger" do
      logger = Argos.current_logger()
      assert logger == Argos.Logger.Default
    end
  end
end

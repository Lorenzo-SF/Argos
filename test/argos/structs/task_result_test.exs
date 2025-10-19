defmodule Argos.Structs.TaskResultTest do
  use ExUnit.Case

  alias Argos.Structs.TaskResult

  describe "success/3" do
    test "creates successful task result" do
      result = TaskResult.success("backup_task", "backup_completed", 1500)

      assert result.task_name == "backup_task"
      assert result.result == "backup_completed"
      assert result.duration == 1500
      assert result.success? == true
      assert result.error == nil
    end

    test "works with atom task names" do
      result = TaskResult.success(:database_task, :ok, 500)

      assert result.task_name == :database_task
      assert result.result == :ok
      assert result.success? == true
    end
  end

  describe "failure/4" do
    test "creates failed task result with string error" do
      result = TaskResult.failure("backup_task", nil, 200, "Connection failed")

      assert result.task_name == "backup_task"
      assert result.result == nil
      assert result.duration == 200
      assert result.success? == false
      assert result.error == "Connection failed"
    end

    test "creates failed task result with exception" do
      exception = %RuntimeError{message: "Something went wrong"}
      result = TaskResult.failure("task", nil, 100, exception)

      assert result.success? == false
      assert result.error == exception
    end
  end

  describe "from_exception/3" do
    test "creates task result from exception" do
      exception = %RuntimeError{message: "Test error"}
      result = TaskResult.from_exception("risky_task", exception, 300)

      assert result.task_name == "risky_task"
      assert result.result == nil
      assert result.duration == 300
      assert result.success? == false
      assert result.error == exception
    end
  end
end

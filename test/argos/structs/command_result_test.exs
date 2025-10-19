defmodule Argos.Structs.CommandResultTest do
  use ExUnit.Case

  alias Argos.Structs.CommandResult

  describe "success/4" do
    test "creates successful command result" do
      result = CommandResult.success("ls", ["-la"], "total 8\n-rw-r--r--", 100)

      assert result.command == "ls"
      assert result.args == ["-la"]
      assert result.output == "total 8\n-rw-r--r--"
      assert result.exit_code == 0
      assert result.duration == 100
      assert result.success? == true
      assert result.error == nil
    end
  end

  describe "failure/6" do
    test "creates failed command result" do
      result =
        CommandResult.failure(
          "invalid_cmd",
          [],
          "command not found",
          127,
          50,
          "Command failed"
        )

      assert result.command == "invalid_cmd"
      assert result.args == []
      assert result.output == "command not found"
      assert result.exit_code == 127
      assert result.duration == 50
      assert result.success? == false
      assert result.error == "Command failed"
    end

    test "creates failed command result without error message" do
      result = CommandResult.failure("cmd", [], "error", 1, 10)

      assert result.success? == false
      assert result.error == nil
    end
  end
end

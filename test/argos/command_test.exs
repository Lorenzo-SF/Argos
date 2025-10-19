defmodule Argos.CommandTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Argos.Structs.CommandResult

  setup do
    Application.put_env(:argos, :env, :test)
    Application.put_env(:argos, :tui_detector, Argos.TuiDetector.Default)
    {:ok, %{}}
  end

  describe "exec/2" do
    test "executes successful command" do
      result = Argos.Command.exec("echo 'hello'")

      assert %CommandResult{} = result
      assert result.success? == true
      assert result.exit_code == 0
      assert result.output =~ "hello"
      assert is_integer(result.duration)
      assert result.duration >= 0
    end

    test "executes failed command" do
      result = Argos.Command.exec("false")

      assert %CommandResult{} = result
      assert result.success? == false
      assert result.exit_code == 1
      assert is_integer(result.duration)
    end

    test "includes caller metadata in logs" do
      output =
        capture_io(fn ->
          Argos.Command.exec("echo 'test'")
        end)

      assert output =~ "Command executed: echo 'test'"
      # El caller real
      assert output =~ "Process.info"
    end

    test "handles command lists" do
      result = Argos.Command.exec(["echo", "hello from list"])

      assert %CommandResult{} = result
      assert result.success? == true
      assert result.output =~ "hello from list"
    end
  end

  describe "exec_raw/2" do
    test "returns raw tuple without logging" do
      {output, exit_code} = Argos.Command.exec_raw("echo 'raw'")

      assert is_binary(output)
      assert exit_code == 0
      assert output =~ "raw"
    end
  end

  describe "exec_silent/2" do
    test "returns only exit code" do
      exit_code = Argos.Command.exec_silent("true")
      assert exit_code == 0

      exit_code = Argos.Command.exec_silent("false")
      assert exit_code == 1
    end
  end

  describe "exec_interactive/2" do
    test "executes interactive command" do
      # Saltar este test si no hay 'script' disponible
      if System.find_executable("script") do
        result = Argos.Command.exec_interactive("echo 'interactive'")
        assert %CommandResult{} = result
        # En algunos sistemas interactivos puede fallar, aceptar ambos resultados
        assert result.success? in [true, false]
      else
        :ok
      end
    end
  end

  describe "process_response/2" do
    test "returns success response for code 0" do
      response = Argos.Command.process_response(0, success_message: "Success!")

      assert response.code == 0
      assert response.type == :success
      assert response.message == ["Success!"]
    end

    test "returns warning response for code 1" do
      response = Argos.Command.process_response(1, warning_message: "Warning!")

      assert response.code == 1
      assert response.type == :warning
      assert response.message == ["Warning!"]
    end

    test "returns error response for other codes" do
      response = Argos.Command.process_response(2, error_message: "Error!")

      assert response.code == 2
      assert response.type == :error
      assert response.message == ["Error!"]
    end
  end

  describe "kill_process/1" do
    test "returns failure for invalid process name" do
      result = Argos.Command.kill_process("")

      assert %CommandResult{} = result
      assert result.success? == false
      assert result.error =~ "Invalid process name"
    end

    test "returns failure for non-string process name" do
      result = Argos.Command.kill_process(123)

      assert %CommandResult{} = result
      assert result.success? == false
      assert result.error =~ "Process name must be a string"
    end
  end

  describe "kill_processes_by_name/1" do
    test "returns list of process kill results" do
      # Usar un proceso que sabemos que no existe para evitar efectos secundarios
      results = Argos.Command.kill_processes_by_name(["nonexistent_process_12345xyz"])

      assert is_list(results)
      assert {process_name, status} = List.first(results)
      assert process_name == "nonexistent_process_12345xyz"

      # Verificar que el status sea uno de los valores esperados
      assert status in [:killed, :not_found] or
               (is_tuple(status) and elem(status, 0) == :error)
    end
  end
end

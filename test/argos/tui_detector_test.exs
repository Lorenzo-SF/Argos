defmodule Argos.TuiDetectorTest do
  use ExUnit.Case, async: false

  alias Argos.TuiDetector

  setup do
    # Guardar configuración original
    original_detector = Application.get_env(:argos, :tui_detector)
    on_exit(fn -> Application.put_env(:argos, :tui_detector, original_detector) end)

    {:ok, %{original_detector: original_detector}}
  end

  describe "tui_mode?/0" do
    test "uses default detector when no custom configured" do
      Application.delete_env(:argos, :tui_detector)

      # Por defecto debería ser false a menos que haya un proceso TUI
      assert TuiDetector.tui_mode?() == false
    end

    test "uses custom detector when configured" do
      defmodule TestTuiDetector do
        @behaviour TuiDetector
        def tui_mode?, do: true
      end

      Application.put_env(:argos, :tui_detector, TestTuiDetector)
      assert TuiDetector.tui_mode?() == true
    end

    test "default detector checks for TUI processes" do
      # Test del detector por defecto directamente
      assert TuiDetector.Default.tui_mode?() == false
    end
  end
end

defmodule Argos.TuiDetector do
  @moduledoc """
  Behaviour for detecting TUI mode in a configurable way.

  This module provides a pluggable interface for detecting whether the application
  is running in TUI (Text User Interface) mode. Different projects can provide
  their own implementations to customize the detection logic according to their
  specific architecture and requirements.

  ## Configuration

  The TUI detector can be configured in your application configuration:

      config :argos,
        tui_detector: MyTuiDetector

  ## Examples

      # Implementing a custom TUI detector
      defmodule MyTuiDetector do
        @behaviour Argos.TuiDetector

        @impl true
        def tui_mode? do
          # Custom logic to detect TUI mode
          Process.whereis(:my_tui_process) != nil
        end
      end

  Then configure it:

      config :argos,
        tui_detector: MyTuiDetector
  """

  @callback tui_mode?() :: boolean()

  @doc """
  Detects if we're in TUI mode using the configured implementation.

  This function retrieves the configured TUI detector from the application
  environment and calls its `tui_mode?/0` function. If no custom detector
  is configured, it uses the default implementation.

  ## Returns

    `true` if in TUI mode, `false` otherwise

  ## Examples

      if Argos.TuiDetector.tui_mode?() do
        # Handle TUI-specific logic
        store_logs_for_tui("Operation complete")
      else
        # Handle console output
        IO.puts("Operation complete")
      end
  """
  def tui_mode? do
    detector = Application.get_env(:argos, :tui_detector, __MODULE__.Default)
    detector.tui_mode?()
  end

  defmodule Default do
    @moduledoc """
    Default implementation of the TUI detector.

    This implementation detects TUI mode by checking for registered processes
    with names that suggest a TUI is active, such as those starting with
    "Tui." or "Aegis.Tui", or specific process names like :tui_main.

    ## Examples

        # This is the default logic used if no custom detector is configured
        if Argos.TuiDetector.Default.tui_mode?() do
          # Handle TUI-specific output
        end
    """

    @behaviour Argos.TuiDetector

    @impl true
    def tui_mode? do
      Process.whereis(:tui_main) != nil ||
        Process.whereis(:tui_supervisor) != nil ||
        Enum.any?(Process.registered(), fn name ->
          name_str = Atom.to_string(name)
          String.starts_with?(name_str, "Tui.") || String.starts_with?(name_str, "Aegis.Tui")
        end)
    end
  end
end

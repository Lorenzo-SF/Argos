defmodule Argos.TuiDetector do
  @moduledoc """
  Behaviour para detectar modo TUI de forma configurable.

  Permite a otros proyectos (como Aegis) proporcionar su propia implementación
  de detección de modo TUI.
  """

  @callback tui_mode?() :: boolean()

  @doc """
  Detecta si estamos en modo TUI usando la implementación configurada.
  """
  def tui_mode? do
    detector = Application.get_env(:argos, :tui_detector, __MODULE__.Default)
    detector.tui_mode?()
  end

  defmodule Default do
    @moduledoc """
    Implementación por defecto del detector de modo TUI.

    Busca procesos registrados con nombres que comiencen con "Tui." o "Aegis.Tui".
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

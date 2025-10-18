defmodule Argos.Log do
  @moduledoc """
  Logger customizado con soporte de colores ANSI, JSON pretty print y limpieza de ANSI.

  - Evita logs en producción.
  - Limpia códigos ANSI.
  - Muestra timestamp, nivel y origen.
  - Pretty print de structs o mapas.
  """

  @behaviour :gen_event
  require Logger

  # ---------------- Callbacks ------------------
  def init(__MODULE__), do: {:ok, %{env: current_env()}}

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    if state.env != :prod do
      try do
        formatted_msg = msg |> format_message()
        formatted_lines = String.split(formatted_msg, "\n", trim: true)

        # Verificar si estamos en modo TUI (buscando si hay un proceso TUI corriendo)
        if in_tui_mode?() do
          # En modo TUI, almacenar logs para mostrarlos de forma no intrusiva
          store_log_messages(level, formatted_lines, ts, md)
        else
          # Fuera de TUI, comportamiento normal
          Enum.each(formatted_lines, &IO.puts(pretty_line(&1, level, ts, md)))
        end
      rescue
        e ->
          if in_tui_mode?() do
            store_log_messages(:error, ["[Argos.Log Error] #{inspect(e)}"], ts, md)
          else
            IO.puts("[Argos.Log Error] #{inspect(e)}")
          end
      end
    end

    {:ok, state}
  end

  def handle_event(_, state), do: {:ok, state}
  def handle_call(_, state), do: {:ok, :ok, state}

  # ---------------- Helpers ------------------
  defp current_env do
    case System.get_env("ARGOS_ENV") do
      "prod" -> :prod
      "dev" -> :dev
      "test" -> :test
      _ -> :dev
    end
  end

  defp format_message(msg) when is_binary(msg), do: clean_ansi(msg)
  defp format_message(msg), do: msg |> inspect(pretty: true) |> clean_ansi()

  # ---------------- Pretty line ------------------
  defp pretty_line(line, level, ts, md) do
    ts_str = format_timestamp(ts)
    module = Keyword.get(md, :module, "Unknown")
    fun = Keyword.get(md, :function, "unknown/0")
    params = Keyword.get(md, :params, nil)

    header = "#{ts_str} #{level_icon(level)} [#{module}.#{fun}]"

    params_str =
      case params do
        nil -> ""
        _ -> " Params: #{inspect(params, limit: 3)}"
      end

    "#{colorize(level, header)} #{line}#{params_str}"
  end

  # ---------------- Icons ------------------
  defp level_icon(:warn), do: "[!]"
  defp level_icon(:warning), do: "[!]"
  defp level_icon(:info), do: "[i]"
  defp level_icon(:debug), do: "[d]"
  defp level_icon(:notice), do: "[n]"
  defp level_icon(:success), do: "[✓]"
  defp level_icon(:error), do: "[X]"
  defp level_icon(:alert), do: "[!A]"
  defp level_icon(:critical), do: "[!C]"
  defp level_icon(:emergency), do: "[!!!]"
  defp level_icon(_), do: "[?]"

  # ---------------- Colors ANSI ------------------
  defp colorize(:info, text), do: "\e[34m#{text}\e[0m"
  defp colorize(:debug, text), do: "\e[36m#{text}\e[0m"
  defp colorize(:warn, text), do: "\e[33m#{text}\e[0m"
  defp colorize(:warning, text), do: "\e[33m#{text}\e[0m"
  defp colorize(:error, text), do: "\e[31m#{text}\e[0m"
  defp colorize(:success, text), do: "\e[32m#{text}\e[0m"
  defp colorize(:notice, text), do: "\e[35m#{text}\e[0m"
  defp colorize(:alert, text), do: "\e[31m#{text}\e[0m"
  defp colorize(:critical, text), do: "\e[31m#{text}\e[0m"
  defp colorize(:emergency, text), do: "\e[41;37m#{text}\e[0m"
  defp colorize(_, text), do: text

  # ---------------- Timestamp ------------------
  defp format_timestamp({{y, mo, d}, {h, m, s, ms}}) do
    "#{pad2(y)}-#{pad2(mo)}-#{pad2(d)} #{pad2(h)}:#{pad2(m)}:#{pad2(s)}.#{pad3(ms)}"
  end

  defp format_timestamp(_), do: "unknown_time"

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"
  defp pad3(n) when n < 10, do: "00#{n}"
  defp pad3(n) when n < 100, do: "0#{n}"
  defp pad3(n), do: "#{n}"

  # ---------------- ANSI cleanup ------------------
  defp clean_ansi(str) do
    str
    |> String.replace(~r/\e\[[\d;?]*[a-zA-Z]/, "")
    |> String.replace(~r/\eP.*?\e\\/, "")
    |> String.trim()
  end

  # ---------------- Public API for Argos ------------------
  def log(level, message, metadata \\ []) do
    Logger.log(level, message, metadata)
  end

  def log_command_execution(command, exit_code, duration, output) do
    Logger.info(
      "Command executed: #{command} (Exit code: #{exit_code}, Duration: #{duration}ms, Output: #{inspect(output) |> clean_ansi()})"
    )
  end

  def log_task_execution(task_name, success?, duration, result) do
    status = if success?, do: "SUCCESS", else: "FAILED"

    Logger.info(
      "Task executed: #{task_name} (Status: #{status}, Duration: #{duration}ms, Result: #{inspect(result) |> clean_ansi()})"
    )
  end

  # ---------------- TUI Mode Detection ------------------
  defp in_tui_mode? do
    # Verificar si hay un proceso del TUI activo
    Process.whereis(:aegis_tui) != nil or
      Enum.any?(Process.registered(), fn name ->
        Atom.to_string(name) |> String.starts_with?("Aegis.Tui")
      end)
  end

  # ---------------- Log Storage for TUI Mode ------------------
  defp store_log_messages(level, lines, ts, _md) do
    # Añadir logs a una cola o archivo temporal
    # En modo TUI, los logs se mostrarán en una sección específica de la UI
    log_entries =
      Enum.map(lines, fn line ->
        "#{format_timestamp(ts)} #{level_icon(level)} [#{inspect(level)}] #{line}
"
      end)

    # Escribir logs a un archivo temporal para que la UI pueda leerlos
    log_dir = Path.join(System.tmp_dir!(), "aegis_logs")
    File.mkdir_p!(log_dir)

    log_file = Path.join(log_dir, "tui_logs.txt")

    Enum.each(log_entries, fn entry ->
      File.write(log_file, entry, [:append])
    end)
  end
end

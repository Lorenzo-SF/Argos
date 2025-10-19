defmodule Argos.Logger.Default do
  @moduledoc """
  Implementación por defecto del logger de Argos.

  Proporciona logging con colores ANSI, formato estructurado y soporte para modo TUI.
  """

  @behaviour Argos.Logger.Behaviour

  @impl true
  def log(level, message, metadata) do
    if Argos.tui_mode?() do
      store_log_for_tui(level, message, metadata)
    else
      print_to_console(level, message, metadata)
    end

    :ok
  end

  @impl true
  def log_command(%Argos.Structs.CommandResult{} = result) do
    metadata = [
      command: result.command,
      exit_code: result.exit_code,
      duration: result.duration,
      success?: result.success?,
      output_preview: String.slice(result.output || "", 0..100)
    ]

    level = if result.success?, do: :info, else: :error
    log(level, "Command: #{result.command}", metadata)
  end

  @impl true
  def log_task(%Argos.Structs.TaskResult{} = result) do
    level = if result.success?, do: :success, else: :error

    metadata = [
      duration: result.duration,
      success?: result.success?,
      error: result.error
    ]

    log(level, "Task: #{result.task_name}", metadata)
  end

  defp print_to_console(level, message, metadata) do
    formatted_message = format_message(message)
    timestamp = format_timestamp()

    {module, function, _file, _line} = extract_caller_info(metadata)

    header = "#{timestamp} #{level_icon(level)} [#{module}.#{function}]"
    colored_header = colorize(level, header)

    formatted_lines = String.split(formatted_message, "\n", trim: true)

    Enum.each(formatted_lines, fn line ->
      IO.puts("#{colored_header} #{line}")
    end)
  end

  defp store_log_for_tui(level, message, metadata) do
    log_dir = Path.join(System.tmp_dir!(), "argos_logs")
    File.mkdir_p!(log_dir)
    log_file = Path.join(log_dir, "tui_logs.txt")

    timestamp = format_timestamp()
    {module, function, _file, _line} = extract_caller_info(metadata)

    entry =
      "#{timestamp} #{level_icon(level)} [#{module}.#{function}] #{format_message(message)}\n"

    File.write!(log_file, entry, [:append])
  end

  defp format_message(message) when is_binary(message), do: clean_ansi(message)
  defp format_message(message), do: message |> inspect(pretty: true) |> clean_ansi()

  defp format_timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp extract_caller_info(metadata) do
    module = Keyword.get(metadata, :module, "Unknown")
    function = Keyword.get(metadata, :function, "unknown/0")
    file = Keyword.get(metadata, :file, "unknown")
    line = Keyword.get(metadata, :line, 0)
    {module, function, file, line}
  end

  defp level_icon(:warn), do: "[!]"
  defp level_icon(:warning), do: "[!]"
  defp level_icon(:info), do: "[i]"
  defp level_icon(:debug), do: "[d]"
  defp level_icon(:notice), do: "[n]"
  defp level_icon(:success), do: "[✓]"
  defp level_icon(:error), do: "[X]"
  defp level_icon(:critical), do: "[!C]"
  defp level_icon(:emergency), do: "[!!!]"
  defp level_icon(_), do: "[?]"

  defp colorize(:info, text), do: "\e[34m#{text}\e[0m"
  defp colorize(:debug, text), do: "\e[36m#{text}\e[0m"
  defp colorize(:warn, text), do: "\e[33m#{text}\e[0m"
  defp colorize(:warning, text), do: "\e[33m#{text}\e[0m"
  defp colorize(:error, text), do: "\e[31m#{text}\e[0m"
  defp colorize(:success, text), do: "\e[32m#{text}\e[0m"
  defp colorize(:notice, text), do: "\e[35m#{text}\e[0m"
  defp colorize(:critical, text), do: "\e[31m#{text}\e[0m"
  defp colorize(:emergency, text), do: "\e[41;37m#{text}\e[0m"
  defp colorize(_, text), do: text

  defp clean_ansi(str) do
    str
    |> String.replace(~r/\e\[[\d;?]*[a-zA-Z]/, "")
    |> String.replace(~r/\eP.*?\e\\/, "")
    |> String.trim()
  end
end

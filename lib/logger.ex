defmodule Argos.Logger do
  @moduledoc """
  Main Argos logger that implements the :logger backend behaviour.

  This module provides a custom logger backend for the Erlang :logger application.
  It acts as a bridge between the standard Elixir/OTP logging system and Argos's
  configurable logging implementations.

  The logger supports:
  - Environment-based log level filtering
  - Integration with custom logger implementations
  - Metadata enrichment and filtering
  - Timestamp formatting
  - Message extraction and formatting

  ## Configuration

  The logger can be configured in your application configuration:

      config :argos,
        logger: MyCustomLogger,
        env: :prod  # or :dev, :test

  ## Examples

      # This module is typically used as part of the :logger configuration
      # and doesn't need to be called directly in most cases
      :logger.add_handler(Argos.Logger, Argos.Logger, %{})
  """

  @behaviour :gen_event

  @impl true
  def init(__MODULE__) do
    logger_impl = Application.get_env(:argos, :logger, Argos.Logger.Default)
    env = current_env()

    {:ok, %{logger_impl: logger_impl, env: env, handler_id: Argos.Logger}}
  end

  @impl true
  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  @impl true
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    if should_log?(state.env, level) do
      try do
        metadata = prepare_metadata(md, ts, level)
        message = extract_message(msg)

        state.logger_impl.log(level, message, metadata)
      rescue
        e ->
          IO.puts(:stderr, "Argos.Logger error: #{inspect(e)}")
      end
    end

    {:ok, state}
  end

  @impl true
  def handle_event(_event, state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:get_config, state) do
    {:ok, state, state}
  end

  @impl true
  def handle_call({:configure, new_config}, state) do
    {:ok, :ok, Map.merge(state, new_config)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  defp should_log?(:prod, level), do: level in [:error, :critical, :emergency, :alert]
  defp should_log?(_env, _level), do: true

  defp current_env do
    case System.get_env("ARGOS_ENV") || Application.get_env(:argos, :env, "dev") do
      "prod" -> :prod
      "dev" -> :dev
      "test" -> :test
      :prod -> :prod
      :dev -> :dev
      :test -> :test
      _ -> :dev
    end
  end

  defp prepare_metadata(md, ts, level) do
    base_md = [
      timestamp: ts,
      level: level,
      handler_id: Argos.Logger
    ]

    useful_md =
      Enum.filter(md, fn
        {:module, _} -> true
        {:function, _} -> true
        {:file, _} -> true
        {:line, _} -> true
        {:application, _} -> true
        {:pid, _} -> true
        _ -> false
      end)

    base_md ++ useful_md
  end

  defp extract_message(msg) when is_binary(msg), do: msg
  defp extract_message({:string, chardata}), do: IO.chardata_to_string(chardata)

  defp extract_message({:fmt, format, args}),
    do: :io_lib.format(format, args) |> IO.chardata_to_string()

  defp extract_message(other), do: inspect(other)
end

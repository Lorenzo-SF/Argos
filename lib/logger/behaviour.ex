defmodule Argos.Logger.Behaviour do
  @moduledoc """
  Behaviour para implementar loggers personalizados en Argos.
  """

  @type level :: :debug | :info | :warn | :error | :critical | :emergency | :success | :notice

  @doc """
  Logea un mensaje con nivel y metadata.
  """
  @callback log(level :: level(), message :: any(), metadata :: keyword()) :: :ok

  @doc """
  Logea el resultado de un comando ejecutado.
  """
  @callback log_command(command_result :: Argos.Structs.CommandResult.t()) :: :ok

  @doc """
  Logea el resultado de una tarea asíncrona.
  """
  @callback log_task(task_result :: Argos.Structs.TaskResult.t()) :: :ok

  @optional_callbacks log_command: 1, log_task: 1
end

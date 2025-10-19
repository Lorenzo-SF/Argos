defmodule Argos.Structs.CommandResult do
  @moduledoc """
  Estructura que representa el resultado de ejecución de un comando.
  """

  @type t :: %__MODULE__{
          command: String.t(),
          args: [String.t()],
          output: String.t(),
          exit_code: non_neg_integer(),
          duration: non_neg_integer(),
          success?: boolean(),
          error: String.t() | nil
        }

  defstruct [
    :command,
    :args,
    :output,
    :exit_code,
    :duration,
    :success?,
    :error
  ]

  @doc """
  Crea un nuevo CommandResult exitoso.
  """
  @spec success(String.t(), [String.t()], String.t(), non_neg_integer()) :: t()
  def success(command, args, output, duration) do
    %__MODULE__{
      command: command,
      args: args,
      output: output,
      exit_code: 0,
      duration: duration,
      success?: true,
      error: nil
    }
  end

  @doc """
  Crea un nuevo CommandResult fallido.
  """
  @spec failure(
          String.t(),
          [String.t()],
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t() | nil
        ) :: t()
  def failure(command, args, output, exit_code, duration, error \\ nil) do
    %__MODULE__{
      command: command,
      args: args,
      output: output,
      exit_code: exit_code,
      duration: duration,
      success?: false,
      error: error
    }
  end
end

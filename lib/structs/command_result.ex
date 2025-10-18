defmodule Argos.Structs.CommandResult do
  @moduledoc """
  Estructura que representa el resultado de ejecución de un comando.

  Esta estructura encapsula toda la información relevante sobre la ejecución
  de un comando del sistema, incluyendo el comando ejecutado, sus argumentos,
  la salida, el código de salida, duración y estado de éxito.
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

  ## Ejemplos

      iex> Argos.Structs.CommandResult.success("ls", ["-la"], "total 8\\n-rw-r--r-- 1 user", 120)
      %Argos.Structs.CommandResult{
        command: "ls",
        args: ["-la"],
        output: "total 8\\n-rw-r--r-- 1 user",
        exit_code: 0,
        duration: 120,
        success?: true,
        error: nil
      }
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

  ## Ejemplos

      iex> Argos.Structs.CommandResult.failure("ls", ["-invalid"], "ls: invalid option", 1, 50)
      %Argos.Structs.CommandResult{
        command: "ls",
        args: ["-invalid"],
        output: "ls: invalid option",
        exit_code: 1,
        duration: 50,
        success?: false,
        error: nil
      }
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

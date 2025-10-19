defmodule Argos.Structs.TaskResult do
  @moduledoc """
  Estructura que representa el resultado de ejecución de una tarea asíncrona.

  Esta estructura encapsula la información sobre la ejecución de una tarea
  asíncrona, incluyendo el nombre de la tarea, el resultado, duración y estado.
  """

  @type t :: %__MODULE__{
          task_name: String.t() | atom(),
          result: any(),
          duration: non_neg_integer(),
          success?: boolean(),
          error: String.t() | Exception.t() | nil
        }

  defstruct [
    :task_name,
    :result,
    :duration,
    :success?,
    :error
  ]

  @doc """
  Crea un nuevo TaskResult exitoso.

  ## Ejemplos

      iex> Argos.Structs.TaskResult.success("backup_database", {:ok, "backup_complete"}, 5000)
      %Argos.Structs.TaskResult{
        task_name: "backup_database",
        result: {:ok, "backup_complete"},
        duration: 5000,
        success?: true,
        error: nil
      }
  """
  @spec success(String.t() | atom(), any(), non_neg_integer()) :: t()
  def success(task_name, result, duration) do
    %__MODULE__{
      task_name: task_name,
      result: result,
      duration: duration,
      success?: true,
      error: nil
    }
  end

  @doc """
  Crea un nuevo TaskResult fallido.

  ## Ejemplos

      iex> Argos.Structs.TaskResult.failure("backup_database", nil, 1200, "Database connection failed")
      %Argos.Structs.TaskResult{
        task_name: "backup_database",
        result: nil,
        duration: 1200,
        success?: false,
        error: "Database connection failed"
      }
  """
  @spec failure(String.t() | atom(), any(), non_neg_integer(), String.t() | Exception.t()) :: t()
  def failure(task_name, result, duration, error) do
    %__MODULE__{
      task_name: task_name,
      result: result,
      duration: duration,
      success?: false,
      error: error
    }
  end

  @doc """
  Crea un TaskResult desde una excepción capturada.

  ## Ejemplos

      iex> try do
      ...>   raise "Something went wrong"
      ...> rescue
      ...>   exception ->
      ...>     Argos.Structs.TaskResult.from_exception("risky_task", exception, 800)
      ...> end
      %Argos.Structs.TaskResult{
        task_name: "risky_task",
        result: nil,
        duration: 800,
        success?: false,
        error: %RuntimeError{message: "Something went wrong"}
      }
  """
  @spec from_exception(String.t() | atom(), Exception.t(), non_neg_integer()) :: t()
  def from_exception(task_name, exception, duration) do
    %__MODULE__{
      task_name: task_name,
      result: nil,
      duration: duration,
      success?: false,
      error: exception
    }
  end
end

defmodule Argos.Structs.TaskResult do
  @moduledoc """
  Estructura que representa el resultado de ejecución de una tarea asíncrona.
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

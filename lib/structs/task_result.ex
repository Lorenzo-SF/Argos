defmodule Argos.Structs.TaskResult do
  @moduledoc """
  Structure that represents the result of asynchronous task execution.

  This struct captures all relevant information from running an asynchronous task,
  whether it's a system command execution or a function execution. It provides
  helper functions to create both successful and failed results, as well as results
  from captured exceptions.

  ## Fields

    * `task_name` - The name of the task (string or atom)
    * `result` - The returned value from the task execution
    * `duration` - Execution time in milliseconds
    * `success?` - Boolean indicating if the task was successful
    * `error` - Optional error message or exception if the task failed

  ## Examples

      # Creating a successful task result
      result = %Argos.Structs.TaskResult{
        task_name: "data_processing",
        result: [1, 2, 3, 4, 5],
        duration: 2500,
        success?: true,
        error: nil
      }

      # Creating a failed task result
      result = Argos.Structs.TaskResult.failure(
        "backup_task", 
        nil, 
        1000, 
        "Failed to write to backup location"
      )

      # Creating a task result from an exception
      try do
        raise "Something went wrong"
      rescue
        exception ->
          result = Argos.Structs.TaskResult.from_exception(
            "error_task", 
            exception, 
            100
          )
      end
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
  Creates a new successful TaskResult.

  ## Parameters

    * `task_name` - The name of the task
    * `result` - The returned value from the task execution
    * `duration` - Execution time in milliseconds

  ## Returns

    A `TaskResult` struct with `success?` set to `true` and `error` set to `nil`

  ## Examples

      result = Argos.Structs.TaskResult.success("my_task", "task completed", 100)
      # %TaskResult{task_name: "my_task", result: "task completed", 
      #             duration: 100, success?: true, error: nil}
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
  Creates a new failed TaskResult.

  ## Parameters

    * `task_name` - The name of the task
    * `result` - The returned value from the task execution (or nil if it failed completely)
    * `duration` - Execution time in milliseconds
    * `error` - Error message or exception describing the failure

  ## Returns

    A `TaskResult` struct with `success?` set to `false` and the error information

  ## Examples

      result = Argos.Structs.TaskResult.failure("failing_task", nil, 500, "Permission denied")
      # %TaskResult{task_name: "failing_task", result: nil, 
      #             duration: 500, success?: false, error: "Permission denied"}
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
  Creates a TaskResult from a captured exception.

  This is useful when you want to convert an exception caught during task execution
  into a structured task result.

  ## Parameters

    * `task_name` - The name of the task where the exception occurred
    * `exception` - The captured exception
    * `duration` - Execution time in milliseconds at the point of failure

  ## Returns

    A `TaskResult` struct representing the failed task with the exception as the error

  ## Examples

      try do
        # Some operation that might fail
        raise "Something went wrong"
      rescue
        exception ->
          result = Argos.Structs.TaskResult.from_exception("my_task", exception, 150)
          # %TaskResult{task_name: "my_task", result: nil, duration: 150, 
          #             success?: false, error: %RuntimeError{message: "Something went wrong"}}
      end
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

defmodule Argos.Task.Progress do
  @moduledoc """
  Progress tracking structure and utilities for long-running tasks.

  This module provides a structured way to track and report progress
  for tasks that execute multiple steps or take significant time to complete.

  ## Features

  - Progress tracking with percentage completion
  - Step-by-step execution tracking
  - Time estimation and remaining time calculation
  - Status management (pending, running, completed, failed, cancelled)
  - Metadata support for additional context

  ## Examples

      # Create a progress tracker
      progress = Argos.Task.Progress.create("database_backup")

      # Update progress during execution
      progress = Argos.Task.Progress.update_step(progress, "Creating backup", 25)

      # Mark as completed
      progress = Argos.Task.Progress.complete(progress, "Backup completed successfully")

      # Format for display
      display_info = Argos.Task.Progress.format_for_display(progress)
  """

  defstruct [
    :task_id,
    :task_name,
    :task_index,
    :status,
    :progress,
    :current_step,
    :step_progress,
    :start_time,
    :duration,
    :estimated_completion,
    :metadata
  ]

  @type status :: :pending | :running | :completed | :failed | :cancelled
  @type t :: %__MODULE__{
          task_id: integer() | nil,
          task_name: String.t(),
          task_index: integer() | nil,
          status: status(),
          progress: float(),
          current_step: String.t() | nil,
          step_progress: float(),
          start_time: integer() | nil,
          duration: integer() | nil,
          estimated_completion: integer() | nil,
          metadata: map()
        }

  @doc """
  Creates a new progress tracker for a task.

  ## Parameters

    * `task_name` - Name of the task being tracked
    * `opts` - Keyword list of options
      - `:task_id` - Unique identifier for the task (default: auto-generated)
      - `:index` - Position index for display purposes

  ## Returns

    A new `Progress` struct in `:pending` state

  ## Examples

      progress = Argos.Task.Progress.create("database_backup")
      # %Progress{task_name: "database_backup", status: :pending, progress: 0.0}

      progress = Argos.Task.Progress.create("backup", index: 0, task_id: 123)
      # %Progress{task_id: 123, task_index: 0, task_name: "backup", status: :pending}
  """
  @spec create(String.t(), keyword()) :: t()
  def create(task_name, opts \\ []) do
    task_id = Keyword.get(opts, :task_id, System.unique_integer([:positive]))
    task_index = Keyword.get(opts, :index)
    start_time = System.monotonic_time(:millisecond)

    %__MODULE__{
      task_id: task_id,
      task_name: task_name,
      task_index: task_index,
      status: :pending,
      progress: 0.0,
      current_step: "Initializing...",
      step_progress: 0.0,
      start_time: start_time,
      duration: 0,
      estimated_completion: nil,
      metadata: %{}
    }
  end

  @doc """
  Updates progress with new information.

  ## Parameters

    * `progress` - The current progress struct
    * `status` - New status (:pending, :running, :completed, :failed, :cancelled)
    * `percentage` - Overall completion percentage (0.0 to 100.0)
    * `step_description` - Description of the current step
    * `opts` - Keyword list of options
      - `:step_progress` - Progress within the current step (0.0 to 100.0)
      - `:metadata` - Additional metadata to merge with existing

  ## Returns

    Updated `Progress` struct

  ## Examples

      progress = Argos.Task.Progress.create("backup")
      progress = Argos.Task.Progress.update(progress, :running, 25.0, "Creating backup")
      # %Progress{status: :running, progress: 25.0, current_step: "Creating backup"}

      progress = Argos.Task.Progress.update(progress, :running, 50.0, "Uploading",
                 step_progress: 75.0, metadata: %{files_processed: 150})
  """
  @spec update(t(), status(), float(), String.t(), keyword()) :: t()
  def update(progress, status, percentage, step_description, opts \\ []) do
    step_progress = Keyword.get(opts, :step_progress, progress.step_progress)
    metadata = Keyword.get(opts, :metadata, %{})

    current_time = System.monotonic_time(:millisecond)
    duration = current_time - (progress.start_time || current_time)

    # Calculate estimated completion if we have meaningful progress
    estimated_completion =
      if percentage > 0 and percentage < 100 do
        elapsed_seconds = duration / 1000
        total_estimated_seconds = elapsed_seconds / (percentage / 100)
        current_time + round((total_estimated_seconds - elapsed_seconds) * 1000)
      else
        progress.estimated_completion
      end

    %__MODULE__{
      progress
      | status: status,
        progress: Float.round(percentage, 1),
        current_step: step_description,
        step_progress: Float.round(step_progress, 1),
        duration: duration,
        estimated_completion: estimated_completion,
        metadata: Map.merge(progress.metadata, metadata)
    }
  end

  @doc """
  Marks a task as started.

  ## Parameters

    * `progress` - The progress struct to update
    * `initial_step` - Description of the initial step (default: "Starting...")

  ## Returns

    Updated `Progress` struct with status `:running`

  ## Examples

      progress = Argos.Task.Progress.create("backup")
      progress = Argos.Task.Progress.start(progress, "Initializing backup process")
      # %Progress{status: :running, current_step: "Initializing backup process"}
  """
  @spec start(t(), String.t()) :: t()
  def start(progress, initial_step \\ "Starting...") do
    update(progress, :running, 0.0, initial_step)
  end

  @doc """
  Updates the current step with progress percentage.

  ## Parameters

    * `progress` - The current progress struct
    * `step_description` - Description of the current step
    * `percentage` - Overall completion percentage
    * `opts` - Keyword list of options
      - `:step_progress` - Progress within the current step

  ## Returns

    Updated `Progress` struct

  ## Examples

      progress = Argos.Task.Progress.start(progress)
      progress = Argos.Task.Progress.update_step(progress, "Processing files", 25.0)
      progress = Argos.Task.Progress.update_step(progress, "Compressing data", 50.0, step_progress: 30.0)
  """
  @spec update_step(t(), String.t(), float(), keyword()) :: t()
  def update_step(progress, step_description, percentage, opts \\ []) do
    step_progress = Keyword.get(opts, :step_progress, percentage)
    update(progress, :running, percentage, step_description, step_progress: step_progress)
  end

  @doc """
  Marks a task as completed.

  ## Parameters

    * `progress` - The progress struct to update
    * `final_message` - Final completion message (default: "Task completed successfully")

  ## Returns

    Updated `Progress` struct with status `:completed` and progress `100.0`

  ## Examples

      progress = Argos.Task.Progress.complete(progress, "Backup completed successfully")
      # %Progress{status: :completed, progress: 100.0, current_step: "Backup completed successfully"}
  """
  @spec complete(t(), String.t()) :: t()
  def complete(progress, final_message \\ "Task completed successfully") do
    update(progress, :completed, 100.0, final_message)
  end

  @doc """
  Marks a task as failed.

  ## Parameters

    * `progress` - The progress struct to update
    * `error_message` - Description of the failure

  ## Returns

    Updated `Progress` struct with status `:failed`

  ## Examples

      progress = Argos.Task.Progress.fail(progress, "Disk full - cannot complete backup")
      # %Progress{status: :failed, current_step: "Failed: Disk full - cannot complete backup"}
  """
  @spec fail(t(), String.t()) :: t()
  def fail(progress, error_message) do
    update(progress, :failed, progress.progress, "Failed: #{error_message}")
  end

  @doc """
  Formats progress for display in UI.

  Converts the progress struct into a simplified map suitable for
  display in user interfaces.

  ## Parameters

    * `progress` - The progress struct to format

  ## Returns

    Map with display-friendly fields:
    * `:id` - Task identifier
    * `:index` - Display index
    * `:description` - Task name
    * `:status` - Current status
    * `:progress` - Completion percentage
    * `:step` - Current step description
    * `:step_progress` - Progress within current step
    * `:duration` - Elapsed time in milliseconds
    * `:estimated_seconds_remaining` - Estimated time remaining in seconds
    * `:metadata` - Additional task metadata

  ## Examples

      progress = Argos.Task.Progress.create("backup", index: 0)
      display_info = Argos.Task.Progress.format_for_display(progress)
      # %{
      #   id: 12345,
      #   index: 0,
      #   description: "backup",
      #   status: :pending,
      #   progress: 0.0,
      #   step: "Initializing...",
      #   duration: 0,
      #   estimated_seconds_remaining: nil,
      #   metadata: %{}
      # }
  """
  @spec format_for_display(t()) :: map()
  def format_for_display(progress) do
    %{
      id: progress.task_id,
      index: progress.task_index,
      description: progress.task_name,
      status: progress.status,
      progress: progress.progress,
      step: progress.current_step,
      step_progress: progress.step_progress,
      duration: progress.duration,
      estimated_seconds_remaining: calculate_remaining_seconds(progress),
      metadata: progress.metadata
    }
  end

  defp calculate_remaining_seconds(progress) do
    if progress.progress > 0 and progress.progress < 100 and progress.estimated_completion do
      max(0, round((progress.estimated_completion - System.monotonic_time(:millisecond)) / 1000))
    else
      nil
    end
  end
end

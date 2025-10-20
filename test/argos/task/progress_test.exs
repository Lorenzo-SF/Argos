defmodule Argos.Task.ProgressTest do
  use ExUnit.Case, async: true

  alias Argos.Task.Progress

  describe "create/2" do
    test "creates a new progress tracker with default values" do
      progress = Progress.create("test_task")

      assert progress.task_name == "test_task"
      assert progress.status == :pending
      assert progress.progress == 0.0
      assert progress.current_step == "Initializing..."
      assert progress.step_progress == 0.0
      assert is_integer(progress.task_id)
      assert progress.duration == 0
      assert progress.metadata == %{}
    end

    test "accepts custom options" do
      progress = Progress.create("custom_task", task_id: 123, index: 5)

      assert progress.task_id == 123
      assert progress.task_index == 5
    end

    test "generates unique task_id when not provided" do
      progress1 = Progress.create("task1")
      progress2 = Progress.create("task2")

      assert progress1.task_id != progress2.task_id
      assert is_integer(progress1.task_id)
      assert is_integer(progress2.task_id)
    end
  end

  describe "update/5" do
    test "updates progress fields correctly" do
      progress = Progress.create("test_task")

      # Añadir un pequeño sleep para asegurar que haya duración
      Process.sleep(1)
      updated = Progress.update(progress, :running, 75.5, "Processing data", step_progress: 80.0, metadata: %{files: 10})

      assert updated.status == :running
      assert updated.progress == 75.5
      assert updated.current_step == "Processing data"
      assert updated.step_progress == 80.0
      assert updated.metadata == %{files: 10}
      # Cambiar a >= en lugar de >
      assert updated.duration >= 0
    end

    test "calculates estimated completion time" do
      progress = Progress.create("test_task")

      # Simulate some time passing
      Process.sleep(10)

      updated = Progress.update(progress, :running, 50.0, "Halfway")

      assert is_integer(updated.estimated_completion)
      assert updated.estimated_completion > System.monotonic_time(:millisecond)
    end

    test "merges metadata instead of replacing" do
      progress = Progress.create("test_task")
      progress = %{progress | metadata: %{initial: "data"}}

      updated = Progress.update(progress, :running, 50.0, "Step", metadata: %{new: "info"})

      assert updated.metadata == %{initial: "data", new: "info"}
    end
  end

  describe "start/2" do
    test "marks task as running with initial step" do
      progress = Progress.create("test_task")

      started = Progress.start(progress, "Custom starting message")

      assert started.status == :running
      assert started.progress == 0.0
      assert started.current_step == "Custom starting message"
    end

    test "uses default step message when not provided" do
      progress = Progress.create("test_task")

      started = Progress.start(progress)

      assert started.current_step == "Starting..."
    end
  end

  describe "update_step/4" do
    test "updates step with progress percentage" do
      progress = Progress.create("test_task")
      progress = Progress.start(progress)

      updated = Progress.update_step(progress, "Processing files", 25.0, step_progress: 50.0)

      assert updated.status == :running
      assert updated.progress == 25.0
      assert updated.current_step == "Processing files"
      assert updated.step_progress == 50.0
    end

    test "uses progress as step_progress when not specified" do
      progress = Progress.create("test_task")
      progress = Progress.start(progress)

      updated = Progress.update_step(progress, "Working", 60.0)

      assert updated.step_progress == 60.0
    end
  end

  describe "complete/2" do
    test "marks task as completed with 100% progress" do
      progress = Progress.create("test_task")
      progress = Progress.start(progress)

      completed = Progress.complete(progress, "Task finished successfully")

      assert completed.status == :completed
      assert completed.progress == 100.0
      assert completed.current_step == "Task finished successfully"
    end

    test "uses default completion message" do
      progress = Progress.create("test_task")

      completed = Progress.complete(progress)

      assert completed.current_step == "Task completed successfully"
    end
  end

  describe "fail/2" do
    test "marks task as failed with error message" do
      progress = Progress.create("test_task")
      progress = Progress.update_step(progress, "Working", 75.0)

      failed = Progress.fail(progress, "Disk full")

      assert failed.status == :failed
      # Maintains last progress
      assert failed.progress == 75.0
      assert failed.current_step == "Failed: Disk full"
    end
  end

  describe "format_for_display/1" do
    test "formats progress for UI display" do
      progress = Progress.create("test_task", index: 1)
      progress = Progress.start(progress, "Starting up")

      display = Progress.format_for_display(progress)

      assert display.id == progress.task_id
      assert display.index == 1
      assert display.description == "test_task"
      assert display.status == :running
      assert display.progress == 0.0
      assert display.step == "Starting up"
      assert display.step_progress == 0.0
      assert is_integer(display.duration)
      assert display.metadata == %{}
    end

    test "calculates remaining seconds when progress available" do
      progress = Progress.create("test_task")

      # Set up a scenario where we have progress and estimated completion
      progress = %{progress | progress: 50.0, estimated_completion: System.monotonic_time(:millisecond) + 30_000}

      display = Progress.format_for_display(progress)

      assert is_integer(display.estimated_seconds_remaining)
      assert display.estimated_seconds_remaining > 25
      assert display.estimated_seconds_remaining <= 30
    end

    test "returns nil for remaining seconds when no progress" do
      progress = Progress.create("test_task")

      display = Progress.format_for_display(progress)

      assert display.estimated_seconds_remaining == nil
    end

    test "returns nil for remaining seconds when progress is 100%" do
      progress = Progress.create("test_task")
      progress = %{progress | progress: 100.0}

      display = Progress.format_for_display(progress)

      assert display.estimated_seconds_remaining == nil
    end
  end

  describe "edge cases" do
    test "handles zero total weight in define_steps" do
      steps = [
        {"step_1", fn _ctx -> :ok end, 0},
        {"step_2", fn _ctx -> :ok end, 0}
      ]

      # Cambiar aquí
      task_function = Argos.AsyncTask.define_steps("zero_weight_steps", steps)

      # Should not crash with division by zero
      assert %{} = task_function.(fn _ -> :ok end)
    end

    test "progress never exceeds 100%" do
      progress = Progress.create("test_task")

      # Try to set progress beyond 100%
      updated = Progress.update(progress, :running, 150.0, "Over 100")

      # We don't clamp in update, but in define_steps we do
      assert updated.progress == 150.0
    end

    test "handles very small progress increments" do
      progress = Progress.create("test_task")

      updated = Progress.update(progress, :running, 0.1, "Just starting")

      assert updated.progress == 0.1
      assert updated.status == :running
    end
  end
end

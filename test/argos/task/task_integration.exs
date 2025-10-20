defmodule Argos.TaskIntegrationTest do
  use ExUnit.Case, async: false

  alias Argos.AsyncTask
  alias Argos.Task.Progress

  @tag :integration
  test "full integration: progress tracking with multi-step tasks" do
    # Define a complex multi-step task
    backup_steps = [
      {"Initialize backup",
       fn _ctx ->
         Process.sleep(10)
         %{backup_id: "backup_123"}
       end, 20},
      {"Create snapshot",
       fn ctx ->
         Process.sleep(10)
         Map.put(ctx, :snapshot, "snapshot_#{ctx.backup_id}")
       end, 30},
      {"Compress data",
       fn ctx ->
         Process.sleep(10)
         Map.put(ctx, :compressed, true)
       end, 25},
      {"Upload to storage",
       fn ctx ->
         Process.sleep(10)
         Map.put(ctx, :uploaded, true)
       end, 25}
    ]

    backup_task = AsyncTask.define_steps("database_backup", backup_steps)
    # Track progress messages
    progress_messages = []
    test_pid = self()

    progress_callback = fn progress ->
      send(test_pid, {:progress, progress.task_name, progress.progress, progress.current_step})
      progress_messages = [progress | progress_messages]
    end

    # Execute with progress tracking
    task_definitions = [{"production_backup", backup_task}]

    assert {:ok, [result]} =
             AsyncTask.run_with_progress(
               task_definitions,
               [max_concurrency: 1],
               progress_callback
             )

    # Verify final result
    assert result.success?
    assert is_binary(result.result.backup_id)
    assert result.result.compressed == true
    assert result.result.uploaded == true

    # Verify progress sequence
    assert_receive {:progress, "database_backup", 0.0, "Initialize backup"}
    assert_receive {:progress, "database_backup", 20.0, "Initialize backup - Completed"}
    assert_receive {:progress, "database_backup", 50.0, "Create snapshot - Completed"}
    assert_receive {:progress, "database_backup", 75.0, "Compress data - Completed"}
    assert_receive {:progress, "database_backup", 100.0, "Upload to storage - Completed"}
    assert_receive {:progress, "database_backup", 100.0, "All steps completed"}
  end

  @tag :integration
  test "mixed task types: commands and progress tasks" do
    task_definitions = [
      {"simple_command", "echo 'hello world'"},
      {"progress_task",
       fn callback ->
         callback.(%Progress{task_name: "progress_task", progress: 0, current_step: "Starting"})
         Process.sleep(10)
         callback.(%Progress{task_name: "progress_task", progress: 100, current_step: "Done"})
         "progress_result"
       end}
    ]

    progress_count = %{count: 0}

    progress_callback = fn _progress ->
      progress_count = %{progress_count | count: progress_count.count + 1}
    end

    # Both should work together
    assert {:ok, results} =
             AsyncTask.run_with_progress(
               task_definitions,
               [],
               progress_callback
             )

    assert length(results) == 2
    assert Enum.all?(results, & &1.success?)
  end
end

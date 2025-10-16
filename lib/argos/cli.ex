defmodule Argos.CLI do
  @moduledoc """
  Command-line interface for Argos command execution and task orchestration library.

  Provides functionality to execute system commands and manage tasks from the command line.
  """

  # Import the Command module to use its functions directly
  import Argos.Command

  alias Argos.{AsyncTask, Log}
  @doc """
  Main entry point for Argos CLI commands.
  """
  def main(argv) do
    argv
    |> parse_args()
    |> process_args()
  end

  defp parse_args(argv) do
    case OptionParser.parse(argv,
      strict: [
        sudo: :boolean,
        task: :keep,
        level: :string,
        metadata: :string,
        max_concurrency: :integer
      ],
      aliases: [
        s: :sudo,
        t: :task
      ]
    ) do
      {opts, args, _errors} ->
        {opts, args}
    end
  end

  defp process_args({opts, args}) do
    command = List.first(args)

    case command do
      "exec" ->
        exec_command(opts, args)

      "raw" ->
        raw_command(opts, args)

      "sudo" ->
        sudo_command(opts, args)

      "parallel" ->
        parallel_command(opts, args)

      "kill" ->
        kill_command(opts, args)

      "ps" ->
        ps_command()

      "log" ->
        log_command(opts, args)

      nil ->
        show_help()

      _ ->
        show_help()
    end
  end

  # Exec command
  defp exec_command(_opts, args) do
    command = Enum.at(args, 1)
    remaining_args = Enum.slice(args, 2..-1)

    if command do
      result = exec!(command, remaining_args)

      if result.success? do
        IO.puts(result.output)
        System.halt(0)
      else
        IO.puts(result.output)
        IO.puts("Error: #{result.exit_code}")
        System.halt(result.exit_code)
      end
    else
      IO.puts("Error: Missing command for exec")
      show_help()
    end
  end

  # Raw command
  defp raw_command(_opts, args) do
    command = Enum.at(args, 1)

    if command do
      result = exec_raw!(command)

      if result.success? do
        IO.puts(result.output)
        System.halt(0)
      else
        IO.puts(result.output)
        IO.puts("Error: #{result.exit_code}")
        System.halt(result.exit_code)
      end
    else
      IO.puts("Error: Missing command for raw")
      show_help()
    end
  end

  # Sudo command
  defp sudo_command(_opts, args) do
    command = Enum.at(args, 1)

    if command do
      result = exec_sudo!(command)

      if result.success? do
        IO.puts(result.output)
        System.halt(0)
      else
        IO.puts(result.output)
        IO.puts("Error: #{result.exit_code}")
        System.halt(result.exit_code)
      end
    else
      IO.puts("Error: Missing command for sudo")
      show_help()
    end
  end

  # Parallel command
  defp parallel_command(opts, _args) do
    tasks_from_opts =
      opts
      |> Keyword.get_values(:task)
      |> Enum.map(fn task ->
        [name, cmd] = String.split(task, ":", parts: 2)
        {name, cmd}
      end)

    if length(tasks_from_opts) > 0 do
      concurrency = Keyword.get(opts, :max_concurrency, 10)
      result = AsyncTask.run_parallel(tasks_from_opts, max_concurrency: concurrency)

      IO.puts("Parallel execution completed:")
      Enum.each(result.results, fn task_result ->
        status = if task_result.success?, do: "SUCCESS", else: "FAILED"
        IO.puts("#{task_result.task_name}: #{status} (#{task_result.duration}ms)")
      end)

      exit_code = if result.all_success?, do: 0, else: 1
      System.halt(exit_code)
    else
      IO.puts("Error: No tasks specified for parallel execution")
      show_help()
    end
  end

  # Kill command
  defp kill_command(_opts, args) do
    process_name = Enum.at(args, 1)

    if process_name do
      result = kill_process(process_name)

      if result.success? do
        IO.puts("Process #{process_name} killed successfully")
        System.halt(0)
      else
        IO.puts("Failed to kill process #{process_name}: #{result.output}")
        System.halt(1)
      end
    else
      IO.puts("Error: Missing process name for kill command")
      show_help()
    end
  end

  # PS command (list processes)
  defp ps_command() do
    # Execute ps command to list processes
    result = exec!("ps", ["aux"])

    if result.success? do
      IO.puts(result.output)
    else
      IO.puts("Error listing processes: #{result.output}")
      System.halt(1)
    end
  end

  # Log command
  defp log_command(opts, args) do
    message = Enum.join(Enum.slice(args, 1..-1), " ")
    level = opts[:level] && String.to_atom(opts[:level]) || :info

    # Parse metadata if provided
    metadata =
      case opts[:metadata] do
        nil -> []
        meta_str ->
          meta_str
          |> String.split(",")
          |> Enum.map(fn pair ->
            [key, value] = String.split(pair, ":", parts: 2)
            {String.to_atom(key), value}
          end)
      end

    Log.log(level, message, metadata)
    System.halt(0)
  end

  defp show_help() do
    help_text = """
    Argos CLI - Command execution and task orchestration tool

    Usage:
      argos [COMMAND] [OPTIONS] [ARGUMENTS]

    Commands:
      exec      Execute a command
                Usage: argos exec ls -la

      raw       Execute a command without additional logging
                Usage: argos raw "pwd"

      sudo      Execute a command with sudo privileges
                Usage: argos sudo "systemctl restart service"

      parallel  Execute multiple tasks in parallel
                Usage: argos parallel --task "name1:command1" --task "name2:command2"

      kill      Kill a process by name
                Usage: argos kill "process_name"

      ps        List system processes
                Usage: argos ps

      log       Log a message
                Usage: argos log "message" --level info --metadata "task_id:123,duration:500"

    Options:
      -s, --sudo              Execute with sudo privileges
      -t, --task NAME:CMD     Task for parallel execution (can be used multiple times)
          --max-concurrency N Maximum number of concurrent tasks (default: 10)
          --level LEVEL       Log level (info, warning, error, debug) (default: info)
          --metadata K:V      Metadata as key:value pairs, comma-separated

    Exit codes:
      0   Success
      1   General error
      N   Command-specific exit code
    """
    IO.puts(help_text)
  end
end

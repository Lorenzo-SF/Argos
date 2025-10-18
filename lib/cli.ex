defmodule Argos.CLI do
  @moduledoc """
  Command-line interface for Argos command execution and task orchestration library.

  Provides access to command execution, parallel tasks, logging, and process management.
  """
  require Logger
  import Argos.Command
  alias Argos.AsyncTask

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
             timeout: :integer,
             max_concurrency: :integer,
             log_level: :string,
             output: :boolean,
             quiet: :boolean
           ],
           aliases: [
             s: :sudo,
             t: :timeout,
             c: :max_concurrency,
             l: :log_level,
             o: :output,
             q: :quiet
           ]
         ) do
      {opts, args, _errors} ->
        {opts, args}
    end
  end

  defp process_args({opts, args}) do
    command = List.first(args)
    subcommand = Enum.at(args, 1)
    execute_command(command, subcommand, opts, args)
  end

  defp execute_command("exec", _, opts, args), do: exec_command(opts, args)
  defp execute_command("exec-sudo", _, opts, args), do: exec_sudo_command(opts, args)
  defp execute_command("exec-raw", _, opts, args), do: exec_raw_command(opts, args)
  defp execute_command("parallel", _, opts, args), do: parallel_command(opts, args)
  defp execute_command("kill", _, _opts, args), do: kill_command(args)

  defp execute_command("log", level, _opts, args)
       when level in ["info", "warn", "error", "debug"],
       do: log_command(level, args)

  defp execute_command("version", _, _opts, _args), do: version()
  defp execute_command(nil, _, _opts, _args), do: show_help()
  defp execute_command(_, _, _opts, _args), do: show_help()

  # Execute command
  defp exec_command(opts, args) do
    case args do
      ["exec" | [_ | _] = command_parts] ->
        command = Enum.join(command_parts, " ")

        result =
          if opts[:sudo] do
            exec_sudo!(command, opts)
          else
            exec!(command, opts)
          end

        handle_command_result(result, opts)

      _ ->
        IO.puts("Error: Missing command for exec")
        show_help()
    end
  end

  # Execute sudo command
  defp exec_sudo_command(opts, args) do
    case args do
      ["exec-sudo" | [_ | _] = command_parts] ->
        command = Enum.join(command_parts, " ")
        result = exec_sudo!(command, opts)
        handle_command_result(result, opts)

      _ ->
        IO.puts("Error: Missing command for exec-sudo")
        show_help()
    end
  end

  # Execute raw command
  defp exec_raw_command(opts, args) do
    case args do
      ["exec-raw" | [_ | _] = command_parts] ->
        command = Enum.join(command_parts, " ")
        result = exec_raw!(command, opts)
        handle_command_result(result, opts)

      _ ->
        IO.puts("Error: Missing command for exec-raw")
        show_help()
    end
  end

  # Execute parallel tasks
  defp parallel_command(opts, args) do
    case args do
      ["parallel" | [_ | _] = task_args] ->
        tasks = parse_parallel_tasks(task_args)
        execute_parallel_tasks(tasks, opts)

      _ ->
        IO.puts("Error: Missing tasks for parallel command")
        show_help()
    end
  end

  defp parse_parallel_tasks(task_args) do
    Enum.map(task_args, &parse_single_task/1)
  end

  defp parse_single_task(task_arg) do
    case String.split(task_arg, ":", parts: 2) do
      [name, cmd] -> {name, cmd}
      [cmd] -> {"task_#{:rand.uniform(1000)}", cmd}
    end
  end

  defp execute_parallel_tasks(tasks, opts) do
    if length(tasks) > 0 do
      result = AsyncTask.run_parallel(tasks, opts)
      display_parallel_results(result, opts)
    else
      IO.puts("Error: No tasks specified for parallel execution")
      show_help()
    end
  end

  defp display_parallel_results(result, opts) do
    if opts[:quiet] do
      show_parallel_summary(result)
    else
      show_parallel_details(result, opts)
    end
  end

  defp show_parallel_summary(result) do
    success_count = Enum.count(result, fn {_, status, _} -> status == :success end)
    total_count = length(result)
    IO.puts("Completed #{success_count}/#{total_count} tasks successfully")
  end

  defp show_parallel_details(result, opts) do
    Enum.each(result, &display_task_result(&1, opts))
  end

  defp display_task_result({name, :success, output}, opts) do
    IO.puts("✓ Task '#{name}' completed successfully")
    if opts[:output] && output, do: IO.puts("  Output: #{inspect(output)}")
  end

  defp display_task_result({name, :error, error}, opts) do
    IO.puts("✗ Task '#{name}' failed")
    if opts[:output] && error, do: IO.puts("  Error: #{inspect(error)}")
  end

  defp display_task_result({name, status, result}, opts) do
    IO.puts("? Task '#{name}' finished with status: #{status}")
    if opts[:output] && result, do: IO.puts("  Result: #{inspect(result)}")
  end

  # Kill process command
  defp kill_command(args) do
    case args do
      ["kill", process_name] when is_binary(process_name) ->
        result = kill_process(process_name)
        handle_command_result(result, [])

      _ ->
        IO.puts("Error: Missing process name for kill command")
        show_help()
    end
  end

  # Log command
  defp log_command(level, args) do
    case args do
      ["log", _level, message] when is_binary(message) ->
        level_atom = String.to_atom(level)
        Logger.log(level_atom, message)
        IO.puts("Logged #{level} message: #{message}")

      _ ->
        IO.puts("Error: Missing message for log command")
        show_help()
    end
  end

  # Version command
  def version do
    config = Mix.Project.config()
    IO.puts("#{config[:app]} v#{config[:version]}")
  end

  # Handle command result output - success case
  defp handle_command_result(%{success?: true, output: output, exit_code: exit_code}, opts) do
    unless opts[:quiet] do
      output_command_result(output, opts)
      IO.puts("Command completed successfully (exit code: #{exit_code})")
    end

    System.halt(0)
  end

  # Handle command result output - failure case
  defp handle_command_result(
         %{success?: false, output: output, exit_code: exit_code, error: error},
         opts
       ) do
    unless opts[:quiet] do
      output_command_result(output, opts)
      IO.puts("Command failed (exit code: #{exit_code})")
      if error, do: IO.puts("Error: #{error}")
    end

    System.halt(exit_code)
  end

  # Handle ok tuple
  defp handle_command_result({:ok, message}, opts) do
    unless opts[:quiet], do: IO.puts(message)
    System.halt(0)
  end

  # Handle error tuple
  defp handle_command_result({:error, error}, opts) do
    unless opts[:quiet], do: IO.puts("Error: #{inspect(error)}")
    System.halt(1)
  end

  # Handle other results
  defp handle_command_result(other, opts) do
    unless opts[:quiet], do: IO.puts("Result: #{inspect(other)}")
    System.halt(0)
  end

  defp output_command_result(output, opts) do
    if opts[:output] || String.trim(output) != "" do
      IO.puts(output)
    end
  end

  defp show_help do
    help_text = """
    Argos CLI - Command execution and task orchestration library

    Usage:
      argos [COMMAND] [OPTIONS] [ARGUMENTS]

    Commands:
      exec              Execute a system command
                       Usage: argos exec "ls -la" --sudo --output

      exec-sudo         Execute a command with sudo privileges
                       Usage: argos exec-sudo "systemctl restart nginx"

      exec-raw          Execute a raw command and return structured result
                       Usage: argos exec-raw "pwd" --output

      parallel          Run multiple tasks in parallel
                       Usage: argos parallel "task1:ls -la" "task2:pwd" --max-concurrency 3

      kill              Kill a process by name
                       Usage: argos kill "nginx"

      log               Log a message with specified level
                       Usage: argos log info "Task completed successfully"
                       Usage: argos log error "Something went wrong"

      version           Show Argos version
                       Usage: argos version

    Options:
      -s, --sudo              Execute command with sudo privileges
      -t, --timeout TIMEOUT   Set timeout in milliseconds for command execution
      -c, --max-concurrency N Maximum number of concurrent tasks for parallel execution
      -l, --log-level LEVEL   Set log level (debug, info, warn, error)
      -o, --output            Show detailed command output
      -q, --quiet             Suppress non-essential output

    Examples:
      argos exec "echo 'Hello World'" --output
      argos exec-sudo "apt-get update" --quiet
      argos parallel "backup:tar -czf backup.tar.gz /data" "cleanup:rm -rf /tmp/old" --max-concurrency 2
      argos kill "node"
      argos log info "Deployment completed successfully"
    """

    IO.puts(help_text)
  end
end

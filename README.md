# Argos

**System command execution and task orchestration library**

[![Version](https://img.shields.io/hexpm/v/argos.svg)](https://hex.pm/packages/argos) [![License](https://img.shields.io/hexpm/l/argos.svg)](https://github.com/usuario/argos/blob/main/LICENSE)

Argos is a lightweight, dependency-free library for executing system commands and managing asynchronous tasks. It provides structured results, configurable logging, and easy-to-use APIs for command execution and task management.

## Features

- 🚀 **System Command Execution** - Execute shell commands with structured results
- ⚡ **Asynchronous Tasks** - Run tasks in parallel with concurrency control
- 📝 **Structured Logging** - Configurable logging with metadata support
- 🛠️ **No External Dependencies** - Completely self-contained
- 🎯 **Result Structs** - Returns structured data instead of raw output for easy processing

## Installation

Add Argos to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:argos, "~> 1.0.0"}
  ]
end
```

## Quick Start

### Command Execution

Execute system commands and get structured results:

```elixir
# Simple command execution
result = Argos.Command.exec("ls -la")
if result.success? do
  IO.puts("Command output: #{result.output}")
  IO.puts("Execution time: #{result.duration}ms")
else
  IO.puts("Command failed with exit code: #{result.exit_code}")
end

# Execute command with custom options
result = Argos.Command.exec("git status", stderr_to_stdout: false)

# Execute command with sudo privileges
result = Argos.Command.exec_sudo("systemctl restart nginx")

# Execute command silently (output redirected to /dev/null)
exit_code = Argos.Command.exec_silent("some_background_command")

# Raw execution (returns {output, exit_code} tuple)
{output, exit_code} = Argos.Command.exec_raw("pwd")
```

### Parallel Task Execution

Run multiple tasks concurrently:

```elixir
# Define tasks as {name, specification} tuples
tasks = [
  {"compile", "mix compile"},
  {"test", {:function, fn -> run_tests() end}},
  {"format", "mix format"}
]

# Execute tasks in parallel with limited concurrency
results = Argos.AsyncTask.run_parallel(tasks, max_concurrency: 2)

# Process results
Enum.each(results.results, fn result ->
  if result.success? do
    IO.puts("Task #{result.task_name} completed in #{result.duration}ms")
  else
    IO.puts("Task #{result.task_name} failed: #{result.error}")
  end
end)
```

### Single Task Execution

Run individual tasks asynchronously:

```elixir
# Execute a function as a task
result = Argos.AsyncTask.run_single("data_processing", fn ->
  # Some processing logic
  Enum.map(1..100, &(&1 * 2))
end)

# Execute command as a task
result = Argos.AsyncTask.run_single("backup", "tar -czf backup.tar.gz /home/user/docs")

# Check task result
if result.success? do
  IO.puts("Task result: #{inspect(result.result)}")
end
```

### Structured Logging

Use the built-in logging system with metadata:

```elixir
# Basic logging
Argos.log(:info, "Application started")

# Logging with metadata
Argos.log(:info, "User action", user_id: 123, action: "login", ip: "192.168.1.1")

# Log command results
result = Argos.Command.exec("ls -la")
Argos.log_command(result)

# Log task results
task_result = Argos.AsyncTask.run_single("my_task", fn -> "completed" end)
Argos.log_task(task_result)
```

## API Overview

### Command Execution (`Argos.Command`)

- `exec/2` - Execute command and return structured result
- `exec_raw/2` - Execute command and return {output, exit_code} tuple
- `exec_silent/2` - Execute command with output suppressed
- `exec_interactive/2` - Execute command in interactive mode
- `exec_sudo/2` - Execute command with sudo privileges
- `kill_process/1` - Kill a process by name
- `kill_processes_by_name/1` - Kill multiple processes by name
- `halt/1` - Halt the system with specified exit code

### Task Management (`Argos.AsyncTask`)

- `run_parallel/2` - Execute multiple tasks in parallel
- `run_single/3` - Execute a single task asynchronously

### Logging (`Argos`)

- `log/3` - Log a message with level and metadata
- `log_command/1` - Log a command result
- `log_task/1` - Log a task result
- `current_logger/0` - Get the current logger implementation
- `tui_mode?/0` - Check if running in TUI mode

## Data Structures

### CommandResult

Represents the result of command execution:

```elixir
%Argos.Structs.CommandResult{
  command: "ls -la",           # The command that was executed
  args: ["-la"],               # Arguments passed to the command
  output: "total 8\n...",      # Command output
  exit_code: 0,                # Exit code (0 for success)
  duration: 150,               # Execution time in milliseconds
  success?: true,              # Whether the command succeeded
  error: nil                   # Error message if any
}
```

### TaskResult

Represents the result of task execution:

```elixir
%Argos.Structs.TaskResult{
  task_name: "my_task",        # Name of the task
  result: "completed",         # Value returned by the task
  duration: 250,               # Execution time in milliseconds
  success?: true,              # Whether the task succeeded
  error: nil                   # Error message or exception if any
}
```

## Configuration

Configure Argos in your application environment:

```elixir
# config/config.exs
import Config

config :argos,
  logger: Argos.Logger.Default,  # Custom logger implementation
  env: :prod,                    # Environment (:dev, :test, :prod)
  shell: "/bin/bash",            # Shell to use for command execution
  tui_detector: Argos.TuiDetector.Default  # TUI mode detector
```

## Custom Loggers

Create custom loggers by implementing the `Argos.Logger.Behaviour`:

```elixir
defmodule MyCustomLogger do
  @behaviour Argos.Logger.Behaviour

  @impl true
  def log(level, message, metadata) do
    # Your custom logging logic
    IO.puts("[#{level}] #{message} - #{inspect(metadata)}")
    :ok
  end

  @impl true
  def log_command(%Argos.Structs.CommandResult{} = result) do
    log(:info, "Command executed: #{result.command}", [
      exit_code: result.exit_code,
      duration_ms: result.duration
    ])
    :ok
  end

  @impl true
  def log_task(%Argos.Structs.TaskResult{} = result) do
    status = if result.success?, do: "SUCCESS", else: "FAILED"
    log(:info, "Task completed: #{result.task_name} - #{status}", [
      duration_ms: result.duration
    ])
    :ok
  end
end
```

## License

Apache 2.0 - See the [LICENSE](LICENSE) file for details.
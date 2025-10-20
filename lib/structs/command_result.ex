defmodule Argos.Structs.CommandResult do
  @moduledoc """
  Structure that represents the result of command execution.

  This struct captures all relevant information from running a system command,
  including the command itself, its output, exit code, execution duration, and
  success status. It provides helper functions to create both successful and
  failed results.

  ## Fields

    * `command` - The executed command as a string
    * `args` - Command arguments as a list of strings
    * `output` - The command output (stdout and stderr)
    * `exit_code` - The exit code returned by the command (0 typically indicates success)
    * `duration` - Execution time in milliseconds
    * `success?` - Boolean indicating if the command was successful (exit_code == 0)
    * `error` - Optional error message if any occurred

  ## Examples

      # Creating a successful command result
      result = %Argos.Structs.CommandResult{
        command: "ls -la",
        args: ["-la"],
        output: "total 8\\n-rw-r--r-- 1 user user 0 Jan 1 12:00 file.txt",
        exit_code: 0,
        duration: 150,
        success?: true,
        error: nil
      }

      # Creating a failed command result
      result = Argos.Structs.CommandResult.failure(
        "ls",
        ["/nonexistent/path"],
        "ls: cannot access '/nonexistent/path': No such file or directory",
        2,
        50
      )

      # Using the success helper function
      result = Argos.Structs.CommandResult.success("echo 'hello'", [], "hello\\n", 10)
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
  Creates a new successful CommandResult.

  ## Parameters

    * `command` - The executed command
    * `args` - Command arguments
    * `output` - Command output
    * `duration` - Execution time in milliseconds

  ## Returns

    A `CommandResult` struct with `exit_code` set to 0 and `success?` set to `true`

  ## Examples

      result = Argos.Structs.CommandResult.success("echo 'hello'", [], "hello\\n", 10)
      # %CommandResult{command: "echo 'hello'", args: [], output: "hello\\n", 
      #                exit_code: 0, duration: 10, success?: true, error: nil}
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
  Creates a new failed CommandResult.

  ## Parameters

    * `command` - The executed command
    * `args` - Command arguments
    * `output` - Command output (if any)
    * `exit_code` - Non-zero exit code indicating failure
    * `duration` - Execution time in milliseconds
    * `error` - Optional error message (default: nil)

  ## Returns

    A `CommandResult` struct with the specified failure details

  ## Examples

      result = Argos.Structs.CommandResult.failure(
        "ls", ["/nonexistent"], "ls: cannot access '/nonexistent': No such file", 2, 50
      )
      # %CommandResult{command: "ls", args: ["/nonexistent"], 
      #                output: "ls: cannot access '/nonexistent': No such file", 
      #                exit_code: 2, duration: 50, success?: false, error: nil}
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

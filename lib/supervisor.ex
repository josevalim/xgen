defmodule Supervisor do
  @moduledoc """
  A behaviour module for implementing supevision functionality.

  A supervisor is a process which supervises other processes called
  child processes. Worker process

  ## Strategies

  * `:one_for_one` - If a child process terminates, only that
    process is restarted;

  * `:one_for_all` - If a child process terminates, all other child
    processes are terminated and then all child processes, including
    the terminated one, are restarted;

  * `:rest_for_one` - If a child process terminates, the "rest" of
    the child processes, i.e. the child processes after the terminated
    process in start order, are terminated. Then the terminated child
    process and the rest of the child processes are restarted;

  * `:simple_one_for_one` - Similar to `:one_for_one` but suits better
    when dynamically attaching children;

  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour :supervisor
      import Supervisor.Spec
    end
  end
end

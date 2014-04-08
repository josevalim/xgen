defmodule Task do
  @moduledoc """
  Conveniences for spawning and awaiting for tasks.

  Tasks are processes that meant to execute one particular
  action throughout their life-cycle, often with little
  explicit communication with other processes. The most common
  use case for tasks is to compute a value asynchronously:

      task = Task.async(fn -> do_some_work() end)
      res  = do_some_other_work()
      res + Task.await(task)

  Tasks spawned with async can be awaited on by its caller
  process (and only its caller) as shown in the example above.
  They are implemented by spawning a process that sends a message
  to the caller once the given computation is performed.

  By providing a common pattern for tasks, we allow other parts
  of the standard library to build on top of tasks. For example,
  a `GenServer.async_call/2` performs a call and returns a task
  that can be waited on to read its result:

      task = GenServer.async_call(:my_server, :pop)
      Task.await(task) #=> :hello

  Besides `async/1` and `await/1`, tasks can also be used as part
  of supervision trees and dynamically spawned in remote nodes.
  We will explore all three scenarios next.

  ## async and await

  The most common way to spawn a task is with `Task.async/1`. A new
  process will be created and this process is linked and monitored
  by the caller. However, the processes are unlinked right before
  the task finishes, allowing the proper error to be triggered only
  on `await/1`.

  This implies three things:

  1) In case the caller crashes, the task will be killed and its
     computation will abort;

  2) In case the task crashes due to an error, the parent will
     crash only on `await/1`;

  3) In case the task crashes because a linked process caused
     it to crash, the parent will crash immediately;

  ## Supervised tasks

  It is also possible to spawn a task inside a supervision tree
  with `start_link/1` and `start_link/3`:

      Task.start_link(fn -> IO.puts "ok" end)

  Such can be mounted in your supervision tree as:

      import Supervisor.Spec

      children = [
        worker(Task, [fn -> IO.puts "ok" end])
      ]

  Since such tasks are supervised and not directly linked to
  the caller, they cannot be awaited on. For such reason,
  differently from `async/1`, `start_link/1` returns `{ :ok, pid }`
  (which is the result expected by supervision trees).

  Such tasks are useful as workers that run during your application
  life-cycle and rarely communicate with other workers. For example,
  a worker that pushes data to another server or a worker that consumes
  events from an event manager and writes it to a log file.

  ## Supervision trees

  The `Task.Sup` module allows developers to start supervisors
  that dynamically supervise tasks:

      { :ok, pid } = Task.Sup.start_link()
      Task.Sup.async(pid, fn -> do_work() end)

  `Task.Sup` also makes it possible to spawn tasks in remote nodes as
  long as the supervisor is registered locally or globally:

      # In the remote node
      Task.Sup.start_link(local: :tasks_sup)

      # On the client
      Task.Sup.async({ :tasks_sup, :remote@local }, fn -> do_work() end)

  `Task.Sup` is more often started in your supervision tree as:

      import Supervisor.Spec

      children = [
        supervisor(Task.Sup, [[local: :tasks_sup]])
      ]

  Check `Task.Sup` for other operations supported by the Task supervisor.
  """

  @doc """
  The Task struct.

  It contains two fields:

  * `:process` - the proces reference of the task process. It may be a pid
    or a tuple containing the process and node names;

  * `:ref` - the task monitor reference;

  """
  defstruct process: nil, ref: nil

  @doc """
  Starts a task as part of a supervision tree.
  """
  @spec start_link(fun) :: { :ok, pid }
  def start_link(fun) do
    start_link(:erlang, :apply, [fun, []])
  end

  @doc """
  Starts a task as part of a supervision tree.
  """
  @spec start_link(module, atom, [term]) :: { :ok, pid }
  def start_link(mod, fun, args) do
    Task.Supervised.start_link(:undefined, { mod, fun, args })
  end

  @doc """
  Starts a task that can be awaited on.

  This function spawns a process that is linked and monitored
  to the caller process. A `Task` struct is returned containing
  the relevant information.

  ## Task's message format

  The reply sent by the task will be in the format `{ ref, msg }`,
  where `ref` is the monitoring reference hold by the task.
  """
  @spec async(fun) :: t
  def async(fun) do
    async(:erlang, :apply, [fun, []])
  end

  @doc """
  Starts a task that can be awaited on.

  Similar to `async/1`, but the task is specified by the given
  module, function and arguments.
  """
  @spec async(module, atom, [term]) :: t
  def async(mod, fun, args) do
    mfa = { mod, fun, args }
    pid = :proc_lib.spawn_link(Task.Supervised, :async, [self(), mfa])
    ref = Process.monitor(pid)
    send(pid, { self(), ref })
    %Task{process: pid, ref: ref}
  end

  @doc """
  Awaits for a task reply.

  A timeout, in miliseconds, can be given with default value
  of `5000`. In case the task process dies, this function will
  exit with the same reason as the task.
  """
  @spec await(t, timeout) :: term
  def await(%Task{process: process, ref: ref}=task, timeout \\ 5000) do
    receive do
      { ^ref, reply } ->
        Process.demonitor(ref, [:flush])
        reply
      { :DOWN, ^ref, _, _, :noconnection } ->
        exit { :nodedown, get_node(process) }, task, timeout
      { :DOWN, ^ref, _, _, :normal } ->
        exit :timeout, task, timeout
      { :DOWN, ^ref, _, _, reason } ->
        exit reason, task, timeout
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit :timeout, task, timeout
    end
  end

  defp exit(reason, task, timeout) do
    exit { reason, { Task, :await, [task, timeout] } }
  end

  defp get_node({ _, n }) when is_atom(n), do: n
  defp get_node(pid) when is_pid(pid),     do: pid
end

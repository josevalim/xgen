defmodule Task do
  @moduledoc """
  Conveniences for spawning and awaiting for tasks.

  A task is a simple pattern of spawning a process to compute
  something asynchronously to read its result later:

      task = Task.async(fn -> do_some_work() end)
      res  = do_some_other_work()
      res + Task.await(task)

  Tasks are implemented by spawning a process that sends a message
  to the caller once the given computation is performed.

  By providing a common pattern for tasks, we allow other parts
  of the standard library to build on top of tasks. For example,
  a `GenServer.async_call/2` performs a call and returns a task
  that can be waited on to read its result:

      task = GenServer.async_call(:my_server, :pop)
      Task.await(task) #=> :hello

  ## async

  The most common way to spawn a task is with `Task.async/1`. A new
  process will be created and this process is linked and monitored
  by the caller. However, the processes are unlinked right before
  the task finishes, so the proper error is triggered on `await/1`.

  This implies three things:

  1) In case the caller crashes, the task will be killed and its
     computation will abort;

  2) In case the task crashes due to an error, the parent will
     crash on `await/1`;

  3) In case the task crashes because a linked process caused
     it to crash, the parent will crash too;

  ## run

  It is also possible to spawn a task for side-effects. The task
  won't be linked nor monitored and can't be waited on.

      Task.run(fn -> IO.puts "ok" end)

  Differently from `async/1`, `run/1` returns the atom `:ok`.

  ## Task's message format

  The reply sent by the task will be in the format `{ ref, msg }`,
  where `ref` is the monitoring reference hold by the task.

  ## Supervised tasks

  The `Task.Sup` module allows developers to start supervisors that
  are meant to supervise tasks. The module also provides API for
  spawning tasks into supervisors:

      { :ok, pid } = Task.Sup.start_link()
      Task.Sup.async(pid, fn -> do_work() end)

  The Task supervisor also gives the opportunity to spawn tasks in remote
  nodes as long as the supervisor is registered locally or globally:

      # In the remote node
      Task.Sup.start_link(local: :tasks_sup)

      # On the client
      Task.Sup.async({ :tasks_sup, :remote@local }, fn -> do_work() end)

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

  @spec run(fun) :: :ok
  def run(fun) do
    Process.spawn(fun)
    :ok
  end

  @spec run(module, atom, [term]) :: :ok
  def run(mod, fun, args) do
    Process.spawn(mod, fun, args)
    :ok
  end

  @spec async(fun) :: t
  def async(fun) do
    async(:erlang, :apply, [fun, []])
  end

  @spec async(module, atom, [term]) :: t
  def async(mod, fun, args) do
    parent = self()

    { pid, ref } =
      Process.spawn(fn ->
        ref = receive do: ({ ^parent, ref } -> ref)
        try do
          send(parent, { ref, apply(mod, fun, args) })
        after
          Process.unlink(parent)
        end
      end, [:link, :monitor])

    send(pid, { parent, ref })
    %Task{process: pid, ref: ref}
  end

  @doc """
  Await for a task reply.

  A timeout, in miliseconds, can be given with default value
  of `5000`. In case the task process dies, this function will
  exit with the same reason as the task.
  """
  @spec await(t, timeout) :: term
  def await(%Task{process: process, ref: ref}, timeout \\ 5000) do
    receive do
      { ^ref, reply } ->
        Process.demonitor(ref, [:flush])
        reply
      { :DOWN, ^ref, _, _, :noconnection } ->
        exit({ :nodedown, get_node(process) })
      { :DOWN, ^ref, _, _, reason } ->
        exit(reason)
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit(:timeout)
    end
  end

  defp get_node({ _, n }) when is_atom(n), do: n
  defp get_node(pid) when is_pid(pid), do: pid
end

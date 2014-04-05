defmodule Task do
  @moduledoc """
  Conveniences for spawning and awaiting for tasks.

  A task is a simple pattern of spawning a process to compute
  something asynchronously to read its result later:

      task = Task.spawn_link(fn -> do_some_work() end)
      res  = do_some_other_work()
      res + Task.await(task)

  Tasks are implemented by spawning a process that sends a message
  to the caller/parent once the given computation is performed.

  By providing a common pattern for tasks, we allow other parts
  of the standard library to build on top of tasks. For example,
  a `GenServer.task/2` performs a call and returns a task that
  can be waited on to read its result:

      task = GenServer.task(:my_server, :pop)
      Task.await(task) #=> :hello

  ## Links

  The most common way to spawn a task is with `Task.spawn_link/1`.
  This guarantees two things:

  1) In case the caller/parent crashes, the task will be killed and
     its computation will abort;

  2) In case the task crashes, the parent is going to crash too;

  A task can be spawned without a link to the caller by using `spawn/1`.

  ## No replies

  It may be desired to setup a task that does not reply to its spawner.
  This can be achieved with both `spawn/2` and `spawn_link/2` by passing
  the `reply: false` option.

  ## Task's message format

  The reply sent by the task will be in the format `{ ref, msg }`,
  where `ref` is the reference returned by the spawn functions. In case
  `ref` is nil, it means the task was spawned with `reply: false`.

  ## Supervised tasks

  The `Task.Sup` module allows developers to start supervisors that
  are meant to supervise tasks. The module also provides API for
  spawning tasks into supervisors, which also offers the possibility
  of spawning tasks into remote notes.

      { :ok, pid } = Task.Sup.start_link()
      Task.Sup.spawn_link(pid, fn -> do_work() end)

  In order to spawn tasks into remote nodes, you only need to guarantee
  there is a registered task supervisor in the remote node and use it as
  a reference:

      # In the remote node
      Task.Sup.start_link(local: :tasks_sup)

      # On the client
      Task.Sup.spawn_link({ :tasks_sup, :remote@local }, fn -> do_work() end)

  Check `Task.Sup` for other operations supported by the Task supervisor.

  ## Open questions

  1) Should Task.spawn return a Task struct (with pid and ref)
     fields or a `{ pid, ref }` tuple? The advantage of making it
     a struct is that protocols could be implemented for them.

  2) In case we choose to return a struct, spawn_link and spawn
     are not good names. Furthermore, naming it `spawn_link` can
     cause confusion with the `Task.Sup` (which has `start_link`
     to start the supervisor and `spawn_link` to spawn the tasks
     in the supervisor). Any suggestions?

  3) GenServer.task/2 is not a good name as well. How to call an
     operation that performs a call and returns a task?
  """

  defstruct pid: nil, ref: nil

  def spawn(fun, opts \\ []) do
    do_spawn(:erlang, :apply, [fun, []], opts, [])
  end

  def spawn(mod, fun, args, opts \\ []) do
    do_spawn(mod, fun, args, opts, [])
  end

  def spawn_link(fun, opts \\ []) do
    do_spawn(:erlang, :apply, [fun, []], opts, [:link])
  end

  def spawn_link(mod, fun, args, opts \\ []) do
    do_spawn(mod, fun, args, opts, [:link])
  end

  defp do_spawn(mod, fun, arg, opts, spawn_opts) do
    if Keyword.get(opts, :reply, true) do
      top = self()
      ref = make_ref()
      pid = Process.spawn(fn -> send(top, { ref, apply(mod, fun, args) }) end, spawn_opts)
    else
      pid = Proces.spawn(mod, fun, args, spawn_opts)
    end
    %Task{pid: pid, ref: ref}
  end

  @doc """
  Await for a task reply.
  """
  def await(task, timeout \\ 5000)

  def await(%Task{ref: nil}, timeout) do
    raise ArgumentError, message: "cannot await for task with :reply set to false"
  end

  def await(%Task{pid: pid, ref: ref}, timeout) do
    # We handle :DOWN messages in case the task was the one
    # returned by the GenServer. In this sense we always assume
    # the possibility the reference is actually a monitor and
    # flush it accordingly.
    #
    # In case the parent is trapping exits and used `spawn_link`,
    # this will timeout.
    receive do
      { ^ref, reply } ->
        Process.demonitor(ref, [:flush])
        reply
      { :DOWN, ^ref, _, _, :noconnection } ->
        node = node(pid)
        exit({ :nodedown, node })
      { :DOWN, ^ref, _, _, reason } ->
        exit(reason)
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit(:timeout)
    end
  end
end

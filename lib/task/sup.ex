defmodule Task.Sup do
  @moduledoc """
  A tasks supervisor.

  This module defines a supervisor which can be used to dynamically
  supervise tasks. Behind the scenes, this module is implemented as a
  `simple_one_for_one` supervisor where the workers are temporary
  (i.e. they are not restarted after they die).

  Once the supervisor is started with `start_link/1`, the remaining
  functions in this module expect a supervisor reference in one of
  the following formats:

  * a `pid`
  * an `atom` if the supervisor is locally registered
  * `{ atom, node }` if the supervisor is locally registered at another node
  * `{ :global, term }` if the supervisor is globally registered
  * `{ :via, module, name }` if the supervisor is registered through an alternative registry

  Tasks can be spawned and awaited as defined in the `Task` module.
  """

  @doc """
  Starts a new supervisor.

  The supported options are:

  * `:local` - the supervivsor is registered locally with the given name (an atom)
    using `Process.register/2`;

  * `:global`- the supervivsor is registered globally with the given term using
    the functions in the `:global` module;

  * `:via` - the supervivsor is registered with the given mechanism and name. The
    `:via` option expects a module name to control the registration mechanism
    and the name in a tuple as option;

  * `:shutdown` - `:brutal_kill` if the tasks must be killed directly on shutdown
    or an integer indicating the timeout value, defaults to 5000 miliseconds;

  """
  @spec start_link(Supervisor.options) :: Supervisor.on_start
  def start_link(opts \\ []) do
    import Supervisor.Spec
    { shutdown, opts } = Keyword.pop(opts, :shutdown, 5000)
    children = [worker(Task.Supervised, [], restart: :temporary, shutdown: shutdown)]
    Supervisor.start_link(children, [strategy: :simple_one_for_one] ++ opts)
  end

  @doc """
  Starts a task that can be awaited on.

  The `supervisor` must be a reference as defined in `Task.Sup`.
  For more information on tasks, check the `Task` module.
  """
  @spec async(Supervisor.supervisor, fun) :: Task.t
  def async(supervisor, fun) do
    async(supervisor, :erlang, :apply, [fun, []])
  end

  @doc """
  Starts a task that can be awaited on.

  The `supervisor` must be a reference as defined in `Task.Sup`.
  For more information on tasks, check the `Task` module.
  """
  @spec async(Supervisor.supervisor, module, atom, [term]) :: Task.t
  def async(supervisor, module, fun, args) do
    mfa = { module, fun, args }
    case whereis(supervisor) do
      :undefined ->
        exit({ :noproc, { __MODULE__, :async, [supervisor, module, fun, args] } })
      pid when node(pid) === node() ->
        local_async(pid, mfa)
      name when is_atom(name) ->
        local_async(name, mfa)
      pid when is_pid(pid) ->
        foreign_async(node(pid), pid, mfa)
      { local_name, node_name } ->
        foreign_async(node_name, local_name, mfa)
    end
  end

  @doc """
  Terminates the given child at pid.
  """
  @spec terminate_child(Supervisor.supervisor, pid) :: :ok
  def terminate_child(supervisor, pid) when is_pid(pid) do
    :supervisor.terminate_child(supervisor, pid)
  end

  @doc """
  Returns all children pids.
  """
  @spec children(Supervisor.supervisor) :: [pid]
  def children(supervisor) do
    :supervisor.which_children(supervisor) |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Starts a task as child of the given `supervisor`.

  Note the spawned process is not linked to the caller but
  only to the supervisor. This command is useful in case the
  task needs to emit side-effects (like I/O) and does not need
  to report back to the caller.
  """
  @spec start_child(Supervisor.supervisor, fun) :: { :ok, pid }
  def start_child(supervisor, fun) do
    start_child(supervisor, :erlang, :apply, [fun, []])
  end

  @doc """
  Starts a task as child of the given `supervisor`.

  Similar to `start_child/2` except the task is specified
  by the given `module`, `fun` and `args`.
  """
  @spec start_child(Supervisor.supervisor, module, atom, [term]) :: { :ok, pid }
  def start_child(supervisor, module, fun, args) do
    Supervisor.start_child(supervisor, [:undefined, { module, fun, args }])
  end

  defp whereis(pid) when is_pid(pid), do: pid
  defp whereis(name) when is_atom(name), do: name
  defp whereis({ :global, name }), do: :global.whereis_name(name)
  defp whereis({ :via, mod, name }), do: mod.whereis_name(name)

  defp whereis({ name, node_name })
      when is_atom(name) and node_name === node() do
    name
  end

  defp whereis({ name, node_name } = process)
      when is_atom(name) and is_atom(node_name) do
    process
  end

  defp local_async(supervisor, mfa) do
    { :ok, pid } = Supervisor.start_child(supervisor, [self(), mfa])
    ref = Process.monitor(pid)
    send pid, { self(), ref }
    %Task{pid: pid, ref: ref}
  end

  # Handle foreign supervisor differently. Need to ensure that starting a task
  # under a supervisor on another node is done cleanly, even if the call fails
  # and is caught. Also want to prevent blocking the supervisor with connection
  # attempts in the init of a task.
  defp foreign_async(node, supervisor, mfa) do
    caller = self()
    { mon_pid, mon_ref } = Process.spawn_monitor(fn() ->
      start_ref = Process.monitor(caller)
      args = [supervisor, mfa, caller, self(), start_ref]
      Node.spawn_link(node, __MODULE__, :foreign_start, args)
      receive do
        { :DOWN, ^start_ref, _, _, reason } -> exit(reason)
      end
    end)
    receive do
      # the message looks like a reply because it could leak on error.
      { start_ref, { ^mon_pid, pid } }->
        Process.demonitor(mon_ref, [:flush])
        # If link/1 raises with :noproc mon_pid will already be dead or about to
        # die due to its link with start_pid (that dies when task pid does).
        Process.link(pid)
        ref = Process.monitor(pid)
        # task pid will receive the exit and match on reason with start_ref to
        # know when to begin the task.
        Process.exit(mon_pid, { start_ref, ref })
        %Task{pid: pid, ref: ref}
      { :DOWN, ^mon_ref, _, _, :noconnection } ->
        args = [node, supervisor, mfa]
        exit({ { :nodedown, node }, { __MODULE__, :foreign_async, args } })
      { :DOWN, ^mon_ref, _, _, reason } ->
        args = [node, supervisor, mfa]
        exit({ reason, { __MODULE__, :foreign_async, args } })
    end
  end

  def foreign_start(supervisor, mfa, caller, mon_pid, start_ref) do
    Process.flag(:trap_exit, true)
    child_args = [caller, mfa, mon_pid, start_ref, self()]
    { :ok, pid } = Supervisor.start_child(supervisor, child_args)
    mon_ref = Process.monitor(pid)
    receive do
      # On successful setup reason will be { start_ref, ref }
      { :EXIT, ^mon_pid, reason } ->
        exit(reason)
      { :DOWN, ^mon_ref, _, _, reason } ->
        exit(reason)
    end
  end

end

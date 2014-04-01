
defmodule Supervisor.Spec do
  @moduledoc """
  Convenience functions for defining a supervision specification.

  ## Example

  By using the functions in this module one can define a supervisor
  and start it with `Supervisor.start_link/2`:

      import Supervisor.Spec

      children = [
        worker(MyWorker, [arg1, arg2, arg3]),
        supervisor(MySupervisor, [arg1])
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  In many situations, it may be handy to define supervisors backed
  by a module:

      defmodule MySupervisor do
        use Supervisor

        def start_link(arg) do
          Supervisor.start_link(__MODULE__, arg)
        end

        def init(arg) do
          children = [
            worker(MyWorker, [arg], restart: :temporary)
          ]

          supervise(children, strategy: :simple_one_for_one)
        end
      end

  Notice in this case we didn't have to explicitly import
  `Supervisor.Spec` as `use Supervisor` automatically does so.

  Explicit supervisors as above are required when there is:

  1. an interest in performing hot-code swaps in the supervision tree;

  2. a need to define supervisors inside other supervisors;

  3. a need to perform actions inside the supervision `init/1` callback.
     For example, you may want to start an ETS table that is linked to
     the supervisor (i.e. if the supervision tree needs to be restarted,
     the ETS table must be restarted too);

  ## Worker and supervisor options

  In the example above, we have defined workers and supervisors
  and each accepts the following options:

  * `:id` - a name used to identify the child specification
    internally by the supervisor. Defaults to the given module
    name;

  * `:function` - the function to invoke on the child to start it.
    Defaults to `:start_link`;

  * `:restart` - defines when the child process should restart.
    Defaults to `:permanent`;

  * `:shutdown` - defines how a child process should be terminated.
    Defaults to `5000` for a worker and `:infinity` for a supervisor;

  * `:modules` - it should be a list with one element `[module]`,
    where module is the name of the callback module only if the
    child process is a `Supervisor` or `GenServer`. If the child
    process is a `GenEvent`, modules should be `:dynamic`.
    Defaults to a list with the given module unless the given
    `module` is `GenEvent` itself.

  ### Restart values

  The following restart values are supported:

  * `:permanent` - the child process is always restarted;

  * `:temporary` - the child process is never restarted (not even
    when the supervisor's strategy is `:rest_for_one` or `:one_for_all`);

  * `:transient` - the child process is restarted only if it
    terminates abnormally, i.e. with another exit reason than
    `:normal`, `:shutdown` or `{ :shutdown, term }`;

  ### Shutdown values

  The following shutdown values are supported:

  * `:brutal_kill` - the child process is unconditionally terminated
    using `exit(child, :kill)`;

  * `:infinity` - if the child process is a supervisor, it is a mechanism
    to give the subtree enough time to shutdown. It can also be used with
    workers with care;

  * Finally, it can also be any integer meaning that the supervisor tells
    the child process to terminate by calling `Process.exit(child, :shutdown)`
    and then waits for an exit signal back. If no exit signal is received
    within the specified time (in miliseconds), the child process is
    unconditionally terminated using `Process.exit(child, :kill)`;
  """

  @doc """
  Receives a list of children (workers or supervisors) to
  supervise and a set of options.

  Returns a tuple containing the supervisor specification.

  ## Examples

      supervise children, strategy: :one_for_one

  ## Options

  * `:strategy` - the restart strategy option It can be either
    `:one_for_one`, `:rest_for_one`, `:one_for_all` and
    `:simple_one_for_one`. You can learn more about strategies
    in the `Supervisor` module;

  * `:max_restarts` - the maximum amount of restarts allowed in
    a time frame. Defaults to 5;

  * `:max_seconds` - the time frame in which max_restarts applies.
    Defaults to 5;

  The `:strategy` option is required and by default maximum 5 restarts
  are allowed in 5 seconds. Please check the `Supervisor` module for
  a complete description of the available strategies.
  """
  def supervise(children, options) do
    unless strategy = options[:strategy] do
      raise ArgumentError, message: "expected :strategy option to be given to supervise"
    end

    maxR = Keyword.get(options, :max_restarts, 5)
    maxS = Keyword.get(options, :max_seconds, 5)

    { :ok, { { strategy, maxR, maxS }, children } }
  end

  @doc """
  Defines the given `module` as a worker which will be started
  with the given arguments.

      worker ExUnit.Runner, [], restart: :permanent

  By default, the function `:start_link` is invoked on the given module.

  Check `Supervisor.Spec` module docs for more information on
  the available options.
  """
  def worker(module, args, options \\ []) do
    child(:worker, module, args, options)
  end

  @doc """
  Defines the given `module` as a supervisor which will be started
  with the given arguments.

      supervisor ExUnit.Runner, [], restart: :permanent

  By default, the function `:start_link` is invoked on the given module.

  Check `Supervisor.Spec` module docs for more information on
  the available options.
  """
  def supervisor(module, args, options \\ []) do
    options = Keyword.put_new(options, :shutdown, :infinity)
    child(:supervisor, module, args, options)
  end

  defp child(type, module, args, options) do
    id       = options[:id]       || id(module)
    modules  = options[:modules]  || modules(module)
    function = options[:function] || :start_link
    restart  = options[:restart]  || :permanent
    shutdown = options[:shutdown] || 5000

    { id, { module, function, args },
      restart, shutdown, type, modules }
  end

  defp id(mod) when mod in [Supervisor] do
    raise ArgumentError, "the :id option is required when the supervisor module is #{inspect mod}"
  end

  defp id(mod) do
    mod
  end

  defp modules(GenEvent), do: :dynamic
  defp modules(module),   do: [module]
end

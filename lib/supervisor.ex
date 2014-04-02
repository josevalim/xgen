defmodule Supervisor do
  @moduledoc """
  A behaviour module for implementing supevision functionality.

  A supervisor is a process which supervises other processes called
  child processes. Supervisors are used to build an hierarchical process
  structure called a supervision tree, a nice way to structure a fault
  tolerant applications.

  A supervisor implemented using this module will have a standard set
  of interface functions and include functionality for tracing and error
  reporting. It will also fit into an supervision tree.

  ## Example

  In order to define a supervisor, we need to first define a child process
  that is going to be supervised. In order to do so, we will define a GenServer
  that represents a stack:

      defmodule Stack do
        use GenServer

        def start_link(state) do
          GenServer.start_link(__MODULE__, state, [local: :sup_stack])
        end

        def handle_call(:pop, _from, [h|t]) do
          { :reply, h, t }
        end

        def handle_cast({ :push, h }, _from, t) do
          { :noreply, [h|t] }
        end
      end

  We can now define our supervisor and start it as follows:

      # Import helpers for defining supervisors
      import Supervisor.Spec

      # We are going to supervise the Stack module which will
      # be started with a single Stack containing [:hello]
      children = [
        worker(Stack, [[:hello]])
      ]

      # Start the supervisor with our one children
      {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

  Notice that when starting the GenServer, we have registered it
  with name `:sup_stack`, which allows us to call it directly and
  get what is on the stack:

      GenServer.call(:sup_stack, :pop)
      #=> :hello

      GenServer.cast(:sup_stack, { :push, :world })
      #=> :ok

      GenServer.cast(:sup_stack, :pop)
      #=> :world

  However, there is a bug in our stack server. If we call `:pop` and
  the stack is empty, it is going to crash because no clause matches.
  Let's try it:

      GenServer.call(:sup_stack, :pop)
      =ERROR REPORT====

  Luckily, since the server is being supervised by a supervisor, the
  supervisor will automatically start a new one, with the default stack
  of `[:hello]` like before:

      GenServer.call(:sup_stack, :pop) == :hello

  Supervisors support different strategies, in the example above, we
  have chosen `:one_for_one`. Furthermore, each supervisor can have many
  workers and supervisors as children, each of them with their specific
  configuration, shutdown values and restart strategies.

  Continue reading this module to learn more about supervision strategies
  and then follow to the `Supervisor.Spec` module documentation to learn
  about the specification for workers and supervisors.

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

  def start_link(children, options) when is_list(children) do
    spec = Supervisor.Spec.supervise(children, options)
    start_link(Supervisor.Simple, spec, options)
  end

  def start_link(module, args, options \\ []) do
    do_start(module, args, options)
  end

  defp do_start(mod, args, [{ :via, { via, name } }|_]) do
    sup_name = { :via, via, name }
    :gen_server.start_link(sup_name, :supervisor, { sup_name, mod, args }, [])
  end

  defp do_start(mod, args, [{ kind, _ } = sup_name|_]) when kind in [:local, :global] do
    :gen_server.start_link(sup_name, :supervisor, { sup_name, mod, args }, [])
  end

  defp do_start(mod, args, [_|t]) do
    do_start(mod, args, t)
  end

  defp do_start(mod, args, []) do
    :gen_server.start_link(:supervisor, { :self, mod, args }, [])
  end
end

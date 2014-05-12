# xgen

**Note:** xgen has been merged into Elixir and will be available from v0.13.3 forward.

When v0.13 was released, we outlined the next steps regarding integrating Elixir and Mix with OTP. The outlined steps were:

1. Integrate application configuration (provided by OTP) right into Mix;
2. Provide an Elixir logger that knows how to print and format Elixir exceptions and stacktraces;
3. Properly expose the functionality provided by Applications, Supervisors, GenServers and GenEvents and study how they can integrate with Elixir. For example, how to consume events from GenEvent as a stream of data?
4. Study how patterns like tasks and agents can be integrated into the language, often picking up the lessons learned by libraries like e2 and functionality exposed by OTP itself;
5. Rewrite the Mix and ExUnit guides to focus on applications and OTP as a whole, rebranding it to "Building Apps with Mix and OTP";

The goal of this project is to explore steps `3` and `4` before their eventual inclusion in Elixir source.

This README provides installation instructions and the overall description of the main modules provided by this library.

## Installation

This project requires Elixir v0.13.1 or later. To install, just add it to your `deps`:

``` elixir
def deps do
  [{:xgen, github: "josevalim/xgen"}]
end
```

And list it as a runtime dependency for your application:

``` elixir
def application do
  [applications: [:xgen]]
end
```

Run `mix deps.get` and you are good to go.

## GenServer

This tool provides a `GenServer` module which is quite similar to the stock gen server provided by Erlang/OTP with two differences:

* Both `start/3` and `start_link/3` expect the module name, the server arguments and a set of options. In order to register the server locally (or globally), a single name option can be used:

   ``` elixir
   GenServer.start_link(MyServer, [], name: MyServer)
   ```


   Treating local and global as options feels more natural than the Erlang syntax:

   ``` elixir
   :gen_server.start_link({:local, MyServer}, MyServer, [], [])
   ```


* A developer can `use GenServer` to get a default implementation for all GenServer callbacks;

In fact, the differences above apply to all other modules below, and as such we won't repeat them in the next modules.

## GenEvent

The main difference that comes with Elixir's GenEvent is that events are streamable:

``` elixir
{:ok, pid} = GenEvent.start_link()
stream = GenEvent.stream(pid)

# Spawn a new process to print the events
spawn_link fn ->
  for event <- stream do
    IO.puts "Got: #{IO.inspect(event)}"
  end
end

GenEvent.notify(pid, :hello)
GenEvent.sync_notify(pid, :world)
```


Streams are guaranteed to be safe since a subscription is only started when streaming starts and, in case the streaming process dies, the handler is removed from the event manager.

Streams also accept two options: `:timeout` which leads to an error if the handler does not receive a message in X milliseconds and `:duration` which controls how long the subscription should live. Streams can also be given ids, allowing them to be cancelled with `GenEvent.cancel_streams(stream)`.

The benefit of such functionality is that events can be published and consumed without the need for callback modules.

## Supervisor

Supervisors in xgen work similarly to OTP's supervisors except by:

1. The addition of `Supervisor.Spec` that helps developers define their supervision tree with clearer options instead of working with tuples;

2. The addition of `Supervisor.start_link/2` which allows supervision trees to be defined without a explicit module with callbacks;

Here is an example:

``` elixir
# Import helpers for defining supervisors
import Supervisor.Spec

# We are going to supervise the Stack server which will
# be started with a argument containing [:hello]
children = [
  worker(Stack, [[:hello]])
]

# Start the supervisor with our one children
{:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
```


## Task

xgen adds a Task module which is useful for spawning processes that compute a value to be retrieved later on:

``` elixir
task = Task.async(fn -> do_some_work() end)
res  = do_some_other_work()
res + Task.await(task)
```


Although tasks map directy to the underlying OTP semantics (using processes), by providing a common pattern, we allow other parts of the standard library to rely on them.

Tasks also ship with a `Task.Supervisor` module, which can be used to supervise tasks and even allow tasks to be spawned on remote nodes:

``` elixir
# In the remote node
Task.Supervisor.start_link(local: :tasks_supervisor)

# On the client
Task.Supervisor.async({:tasks_supervisor, :remote@local}, fn -> do_work() end)
```


This is similar to the `:rpc` funcitonality except you have explicitly control of the supervisor (instead of an internal `:rex` one) also allowing tasks to be supervised dynamically.

## Agent

Agents are a simple abstraction around state.

Often in Elixir there is a need to share or store state that must be accessed from different processes or by a same process in different points in time.

The Agent module provides a basic server implementation that allows state to be retrieved and updated via a simple API. For example, in the Mix tool that ships with Elixir, we need to keep a set of all tasks executed by a given project. Since this set is shared, we can implement it with an Agent:

``` elixir
defmodule Mix.TasksServer do
  def start_link do
    Agent.start_link(fn -> HashSet.new end, local: __MODULE__)
  end

  @doc "Checks if the task has already executed"
  def executed?(task, project) do
    item = {task, project}
    Agent.get(__MODULE__, fn set ->
      item in set
    end)
  end

  @doc "Marks a task as executed"
  def put_task(task, project) do
    item = {task, project}
    Agent.update(__MODULE__, &Set.put(item, &1))
  end
end
```


Note that agents still provide a segregation in between the client and server APIs, as seen in GenServers. In particular, all code inside the function passed to the agent is executed by the agent. This distinction is important because you may want to avoid expensive operations inside the agent, as it will effectively block the agent until the request is fullfilled.

## License

This project is released under the same LICENSE and Copyright as Elixir.

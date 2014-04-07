# xgen

When v0.13 was released, we outlined the next steps regarding integrating Elixir and Mix with OTP. The outlined steps were:

1. Integrate application configuration (provided by OTP) right into Mix;
2. Provide an Elixir logger that knows how to print and format Elixir exceptions and stacktraces;
3. Properly expose the functionality provided by Applications, Supervisors, GenServers and GenEvents and study how they can integrate with Elixir. For example, how to consume events from GenEvent as a stream of data?
4. Study how patterns like tasks and agents can be integrated into the language, often picking up the lessons learned by libraries like e2 and functionality exposed by OTP itself;
5. Rewrite the Mix and ExUnit guides to focus on applications and OTP as a whole, rebranding it to "Building Apps with Mix and OTP";

The goal of this project is to explore steps `3` and `4` before their eventual inclusion in Elixir source.

This README provides installation instructions and the overall description of the main modules provided by this library.

## Installation

This project requires Elixir v0.13.0 or later. To install, just add it to your `deps`:

    def deps do
      [{:xgen, github: "josevalim/xgen"}]
    end

And list it as a runtime dependency for your application:

    def application do
      [applications: [:xgen]]
    end

Run `mix deps.get` and you are good to go.

## GenServer

This tool provides a `GenServer` module which is quite similar to the stock gen server provided by Erlang/OTP with two differences:

* Both `start/3` and `start_link/3` expect the module name, the server arguments and a set of options. In order to register the server locally (or globally), an option needs to be given:

        GenServer.start_link(MyServer, [], local: MyServer)

   Treating local and global as options feels more natural than the Erlang syntax:

        :gen_server.start_link({ :local, MyServer }, MyServer, [], [])

* A developer can `use GenServer` to get a default implementation for all GenServer callbacks;

In fact, the differences above apply to all other modules below, and as such we won't repeat them in the next modules.

## GenEvent

The main difference that comes with Elixir's GenEvent is that events are streamable:

    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid)

    # Spawn a new process to print the events
    spawn_link fn ->
      for event <- stream do
        IO.puts "Got: #{IO.inspect(event)}"
      end
    end

    GenEvent.notify(pid, :hello)
    GenEvent.sync_notify(pid, :world)

Streams are guaranteed to be safe since a subscription is only started when streaming starts and, in case the streaming process dies, the handler is removed from the event manager.

Streams also accept two options: `:timeout` which leads to an error if the handler does not receive a message in X milliseconds and `:duration` which controls how long the subscription should live. Streams can also be given ids, allowing them to be cancelled with `GenEvent.cancel_streams(stream)`.

The benefit of such functionality is that events can be published and consumed without the need for callback modules, which is useful for short-term/simple subscription schemas.

## Supervisor

Supervisors in xgen work similarly to OTP's supervisors except by:

1. The addition of `Supervisor.Spec` that helps developers define their supervision tree with clearer options;

2. The addition of `Supervisor.start_link/2` which allows supervision trees to be defined without a explicit module with callbacks;

## Application

...

## Task

xgen adds a Task module which is useful for spawning processes that compute a value to be retrieved later on:

    task = Task.async(fn -> do_some_work() end)
    res  = do_some_other_work()
    res + Task.await(task)

Although tasks map directy to the underlying OTP semantics (using processes), by providing a common pattern, we allow other parts of the standard library to rely on them. For example, `GenServer.async_call/2` performs a `call/2` operation and returns a Task struct that can be awaited on.

Tasks also ship with a `Task.Sup` module, which can be used to supervise tasks and even allow tasks to be spawned on remote nodes:

    # In the remote node
    Task.Sup.start_link(local: :tasks_sup)

    # On the client
    Task.Sup.async({ :tasks_sup, :remote@local }, fn -> do_work() end)

## Agent

...

## License

This project is released under the same LICENSE and Copyright as Elixir.

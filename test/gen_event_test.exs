defmodule GenEventTest do
  use ExUnit.Case, async: true

  defmodule LoggerHandler do
    use GenEvent

    def handle_event({:log, x}, messages) do
      { :ok, [x|messages] }
    end

    def handle_call(:messages, messages) do
      { :ok, Enum.reverse(messages), [] }
    end
  end

  @receive_timeout 1000

  test "start_link/2 and handler workflow" do
    { :ok, pid } = GenEvent.start_link()

    { :links, links } = Process.info(self, :links)
    assert pid in links

    assert GenEvent.notify(pid, { :log, 0 }) == :ok
    assert GenEvent.add_handler(pid, LoggerHandler, []) == :ok
    assert GenEvent.notify(pid, { :log, 1 }) == :ok
    assert GenEvent.notify(pid, { :log, 2 }) == :ok

    assert GenEvent.call(pid, LoggerHandler, :messages) == [1, 2]
    assert GenEvent.call(pid, LoggerHandler, :messages) == []

    assert GenEvent.remove_handler(pid, LoggerHandler, []) == :ok
    assert GenEvent.stop(pid) == :ok
  end

  test "start/2 with linked handler" do
    { :ok, pid } = GenEvent.start()

    { :links, links } = Process.info(self, :links)
    refute pid in links

    assert GenEvent.add_handler(pid, LoggerHandler, [], link: true) == :ok

    { :links, links } = Process.info(self, :links)
    assert pid in links

    assert GenEvent.notify(pid, { :log, 1 }) == :ok
    assert GenEvent.sync_notify(pid, { :log, 2 }) == :ok

    assert GenEvent.call(pid, LoggerHandler, :messages) == [1, 2]
    assert GenEvent.stop(pid) == :ok
  end

  test "start/2 with linked swap" do
    { :ok, pid } = GenEvent.start()

    assert GenEvent.add_handler(pid, LoggerHandler, []) == :ok

    { :links, links } = Process.info(self, :links)
    refute pid in links

    assert GenEvent.swap_handler(pid, LoggerHandler, [], LoggerHandler, [], link: true) == :ok

    { :links, links } = Process.info(self, :links)
    assert pid in links

    assert GenEvent.stop(pid) == :ok
  end

  test "start/2 with registered name" do
    { :ok, _ } = GenEvent.start(local: :logger)
    assert GenEvent.stop(:logger) == :ok
  end

  test "stream/2 is enumerable" do
    # Start a manager
    { :ok, pid } = GenEvent.start_link()

    # Also start multiple subscribers
    parent = self()
    spawn_link fn -> send parent, Enum.take(GenEvent.stream(pid), 5) end
    spawn_link fn -> send parent, Enum.take(GenEvent.stream(pid), 3) end
    wait_for_handlers(pid, 2)

    # Notify the events
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end

    # Receive one of the results
    assert_receive  [1, 2, 3], @receive_timeout
    refute_received [1, 2, 3, 4, 5]

    # Push the remaining events
    for i <- 4..10 do
      GenEvent.sync_notify(pid, i)
    end

    assert_receive [1, 2, 3, 4, 5], @receive_timeout

    # Both subscriptions are gone
    wait_for_handlers(pid, 0)
    GenEvent.stop(pid)
  end

  test "stream/2 with timeout" do
    # Start a manager
    { :ok, pid } = GenEvent.start_link()

    # Start a subscriber with timeout
    parent = self()
    spawn_link fn ->
      send parent, (try do
        Enum.take(GenEvent.stream(pid, timeout: 50), 5)
      catch
        :exit, :timeout -> :timeout
      end)
    end

    assert_receive :timeout, @receive_timeout
  end

  test "stream/2 with error/timeout on subscription" do
    # Start a manager
    { :ok, pid } = GenEvent.start_link()

    # Start a subscriber with timeout
    child = spawn fn -> Enum.to_list(GenEvent.stream(pid)) end
    wait_for_handlers(pid, 1)

    # Kill and wait until we have 0 handlers
    Process.exit(child, :kill)
    wait_for_handlers(pid, 0)
    GenEvent.stop(pid)
  end

  test "stream/2 with manager stop" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()

    parent = self()
    spawn_link fn -> send parent, Enum.take(GenEvent.stream(pid), 5) end
    wait_for_handlers(pid, 1)

    # Notify the events
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end

    GenEvent.stop(pid)
    assert_receive [1, 2, 3], @receive_timeout
  end

  test "stream/2 with cancel streams" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid, id: make_ref())

    parent = self()
    spawn_link fn -> send parent, Enum.take(stream, 5) end
    wait_for_handlers(pid, 1)

    # Notify the events
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end

    GenEvent.cancel_streams(stream)
    assert_receive [1, 2, 3], @receive_timeout
    GenEvent.stop(pid)
  end

  test "stream/2 with duration" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid, duration: 200)

    parent = self()
    spawn_link fn -> send parent, { :duration, Enum.take(stream, 10) } end
    wait_for_handlers(pid, 1)

    # Notify the events
    for i <- 1..5 do
      GenEvent.sync_notify(pid, i)
    end

    # Wait until the handler is gone
    wait_for_handlers(pid, 0)

    # The stream is not complete but terminated anyway due to duration
    receive do
      { :duration, list } when length(list) <= 5 -> :ok
    after
      0 -> flunk "expected event stream to have finished with 5 or less items"
    end

    GenEvent.stop(pid)
  end

  test "stream/2 with duration and manager stop" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid, duration: 200)

    parent = self()
    spawn_link fn -> send parent, Enum.take(stream, 5) end
    wait_for_handlers(pid, 1)

    # Notify the events
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end

    GenEvent.stop(pid)
    assert_receive [1, 2, 3], @receive_timeout

    # Timeout message does not leak
    refute_received { :timeout, _, __MODULE__ }
  end

  test "stream/2 with parallel use and first finishing first" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid, duration: 200)

    parent = self()
    spawn_link fn -> send parent, { :take, Enum.take(stream, 3) } end
    wait_for_handlers(pid, 1)
    spawn_link fn -> send parent, { :to_list, Enum.to_list(stream) } end
    wait_for_handlers(pid, 2)

    # Notify the events for both handlers
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end
    assert_receive { :take, [1, 2, 3] }, @receive_timeout

    # Notify the events for to_list stream handler
    for i <- 4..5 do
      GenEvent.sync_notify(pid, i)
    end

    assert_receive { :to_list, [1, 2, 3, 4, 5] }, @receive_timeout
  end

  test "stream/2 with manager killed and trap_exit" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link()
    stream = GenEvent.stream(pid)

    parent = self()
    spawn_link fn ->
      Process.flag(:trap_exit, true)
      send parent, Enum.to_list(stream)
    end
    wait_for_handlers(pid, 1)

    trap = Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    assert_receive { :EXIT, ^pid, :killed }, @receive_timeout
    Process.flag(:trap_exit, trap)

    assert_receive [], @receive_timeout
  end

  test "stream/2 with manager unregistered" do
    # Start a manager and subscribers
    { :ok, pid } = GenEvent.start_link(local: :unreg)
    stream = GenEvent.stream(:unreg)

    parent = self()
    spawn_link fn ->
      send parent, Enum.take(stream, 5)
    end
    wait_for_handlers(pid, 1)

    # Notify the events
    for i <- 1..3 do
      GenEvent.sync_notify(pid, i)
    end

    # Unregister the process
    Process.unregister(:unreg)

    # Notify the remaining events
    for i <- 4..5 do
      GenEvent.sync_notify(pid, i)
    end

    # We should have gotten the message and all handlers were removed
    assert_receive [1, 2, 3, 4, 5], @receive_timeout
    wait_for_handlers(pid, 0)
  end

  defp wait_for_handlers(pid, count) do
    unless length(GenEvent.which_handlers(pid)) == count do
      wait_for_handlers(pid, count)
    end
  end
end

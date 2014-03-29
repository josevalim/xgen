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

    assert GenEvent.add_handler(pid, LoggerHandler, [])

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
end

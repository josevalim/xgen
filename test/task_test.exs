defmodule TaskTest do
  use ExUnit.Case, async: true

  def atom(atom), do: atom

  test "async/1" do
    task = Task.async fn ->
      receive do: (true -> true)
      :done
    end

    # Assert the struct
    assert task.__struct__ == Task
    assert is_pid task.process
    assert is_reference task.ref

    # Assert the link
    { :links, links } = Process.info(self, :links)
    assert task.process in links

    # Run the task
    send task.process, true

    # Assert response and monitoring messages
    ref = task.ref
    assert_receive { ^ref, :done }
    assert_receive { :DOWN, ^ref, _, _, :normal }
  end

  test "async/3" do
    task = Task.async(__MODULE__, :atom, [:done])
    assert task.__struct__ == Task
    assert Task.await(task) == :done
  end

  test "run/1" do
    parent = self()
    assert Task.run(fn -> send(parent, :done) end) == :ok
    assert_receive :done
  end

  test "run/3" do
    assert Task.run(Kernel, :send, [self, :done]) == :ok
    assert_receive :done
  end

  test "await/1 exits on timeout" do
    task = %Task{ref: make_ref()}
    assert catch_exit(Task.await(task, 0)) == :timeout
  end

  test "await/1 exits with timeout on normal task exit" do
    task = Task.async(fn -> exit :normal end)
    assert catch_exit(Task.await(task)) == :timeout
  end

  test "await/1 exits on task exit" do
    task = Task.async(fn -> exit :unknown end)
    assert catch_exit(Task.await(task)) == :unknown
  end

  test "await/1 exits on :noconnection" do
    node = { :unknown, :unknown@node }
    assert catch_exit(noconnection(node)) == {:nodedown, :unknown@node}
    assert catch_exit(noconnection(self)) == {:nodedown, self}
  end

  defp noconnection(process) do
    ref  = make_ref()
    task = %Task{ref: ref, process: process}
    send self(), { :DOWN, ref, process, self(), :noconnection }
    Task.await(task)
  end
end

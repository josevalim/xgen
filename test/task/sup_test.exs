defmodule Task.SupTest do
  use ExUnit.Case, async: true

  setup do
    { :ok, _ } = Task.Sup.start_link(local: :task_sup)
    :ok
  end

  teardown do
    Process.exit(Process.whereis(:task_sup), :shutdown)
    :ok
  end

  def wait_and_send(caller, atom) do
    receive do: (true -> true)
    send caller, atom
  end

  test "async/1" do
    task = Task.Sup.async :task_sup, fn ->
      receive do: (true -> true)
      :done
    end

    assert Task.Sup.children(:task_sup) == [task.process]

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
    task = Task.Sup.async(:task_sup, List, :flatten, [[1, [2], 3]])
    assert Task.Sup.children(:task_sup) == [task.process]

    assert task.__struct__ == Task
    assert Task.await(task) == [1, 2, 3]
  end

  test "start_child/1" do
    parent = self()
    { :ok, pid } = Task.Sup.start_child(:task_sup, fn -> wait_and_send(parent, :done) end)
    assert Task.Sup.children(:task_sup) == [pid]

    { :links, links } = Process.info(self, :links)
    refute pid in links

    send pid, true
    assert_receive :done
  end

  test "start_child/3" do
    { :ok, pid } = Task.Sup.start_child(:task_sup, __MODULE__, :wait_and_send, [self(), :done])
    assert Task.Sup.children(:task_sup) == [pid]

    { :links, links } = Process.info(self, :links)
    refute pid in links

    send pid, true
    assert_receive :done
  end

  test "terminate_child/2" do
    { :ok, pid } = Task.Sup.start_child(:task_sup, __MODULE__, :wait_and_send, [self(), :done])
    assert Task.Sup.children(:task_sup) == [pid]
    assert Task.Sup.terminate_child(:task_sup, pid) == :ok
    assert Task.Sup.children(:task_sup) == []
    assert Task.Sup.terminate_child(:task_sup, pid) == :ok
  end

  test "await/1 exits on task throw" do
    task = Task.Sup.async(:task_sup, fn -> throw :unknown end)
    assert { { { :nocatch, :unknown }, _ }, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end

  test "await/1 exits on task error" do
    task = Task.Sup.async(:task_sup, fn -> raise "oops" end)
    assert { { RuntimeError[], _ }, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end

  test "await/1 exits on task exit" do
    task = Task.Sup.async(:task_sup, fn -> exit :unknown end)
    assert { :unknown, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end
end

defmodule Task.SupTest do
  use ExUnit.Case, async: true

  setup do
    { :ok, pid } = Task.Sup.start_link()
    { :ok, sup: pid }
  end

  teardown config do
    Process.exit(config[:sup], :shutdown)
    :ok
  end

  def wait_and_send(caller, atom) do
    receive do: (true -> true)
    send caller, atom
  end

  test "async/1", config do
    task = Task.Sup.async config[:sup], fn ->
      receive do: (true -> true)
      :done
    end

    assert Task.Sup.children(config[:sup]) == [task.pid]

    # Assert the struct
    assert task.__struct__ == Task
    assert is_pid task.pid
    assert is_reference task.ref

    # Assert the link
    { :links, links } = Process.info(self, :links)
    assert task.pid in links

    # Run the task
    send task.pid, true

    # Assert response and monitoring messages
    ref = task.ref
    assert_receive { ^ref, :done }
    assert_receive { :DOWN, ^ref, _, _, :normal }
  end

  test "async/3", config do
    task = Task.Sup.async(config[:sup], __MODULE__, :wait_and_send, [self(), :done])
    assert Task.Sup.children(config[:sup]) == [task.pid]

    send task.pid, true
    assert task.__struct__ == Task
    assert Task.await(task) == :done
  end

  test "start_child/1", config do
    parent = self()
    { :ok, pid } = Task.Sup.start_child(config[:sup], fn -> wait_and_send(parent, :done) end)
    assert Task.Sup.children(config[:sup]) == [pid]

    { :links, links } = Process.info(self, :links)
    refute pid in links

    send pid, true
    assert_receive :done
  end

  test "start_child/3", config do
    { :ok, pid } = Task.Sup.start_child(config[:sup], __MODULE__, :wait_and_send, [self(), :done])
    assert Task.Sup.children(config[:sup]) == [pid]

    { :links, links } = Process.info(self, :links)
    refute pid in links

    send pid, true
    assert_receive :done
  end

  test "terminate_child/2", config do
    { :ok, pid } = Task.Sup.start_child(config[:sup], __MODULE__, :wait_and_send, [self(), :done])
    assert Task.Sup.children(config[:sup]) == [pid]
    assert Task.Sup.terminate_child(config[:sup], pid) == :ok
    assert Task.Sup.children(config[:sup]) == []
    assert Task.Sup.terminate_child(config[:sup], pid) == :ok
  end

  test "await/1 exits on task throw", config do
    task = Task.Sup.async(config[:sup], fn -> throw :unknown end)
    assert { { { :nocatch, :unknown }, _ }, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end

  test "await/1 exits on task error", config do
    task = Task.Sup.async(config[:sup], fn -> raise "oops" end)
    assert { { RuntimeError[], _ }, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end

  test "await/1 exits on task exit", config do
    task = Task.Sup.async(config[:sup], fn -> exit :unknown end)
    assert { :unknown, { Task, :await, [^task, 5000] } } =
           catch_exit(Task.await(task))
  end

  test "async/4 cross node with netsplit" do
    { :ok, _ } = :net_kernel.start([:"foo@127.0.0.1", :longnames, 1000])
    bar = setup_node(:bar)
    buzz = setup_node(:buzz)
    # start Task.Sup
    { :ok, sup_pid } = :rpc.block_call(bar, Task.Sup, :start_link, [])
    # suspend Task.Sup so it doesn't handle requests
    :sys.suspend(sup_pid)
    trap = Process.flag(:trap_exit, true)
    pid = spawn_link( fn() ->
      # use block_call so :rex catches failure and stays alive
      { :badrpc, { :EXIT, reason } } = :rpc.block_call(buzz, Task.Sup, :async,
        [sup_pid, :erlang, :now, []])
      exit(reason)
    end)
    # sleep to ensure message in sup_pid queue
    :timer.sleep(200)
    # break connection between bar and buzz
    true = :rpc.call(bar, :erlang, :disconnect_node, [buzz])
    # :rex on buzz caught the failed attempt to spawn a task
    assert_receive { :EXIT, ^pid, { { :nodedown, ^bar }, _ } }
    Process.flag(:trap_exit, trap)
    # resume Task.Sup so it spawns the task.
    :sys.resume(sup_pid)
    # the task on bar will try to link to its caller process on buzz and
    # reconnection will occur and the link will be successful.
    # sleep for a while to let the dust settle.
    :timer.sleep(1000)
    # check the spawned task has exited
    assert Supervisor.which_children(sup_pid) == []
    :slave.stop(bar)
    :slave.stop(buzz)
    :net_kernel.stop()
  end

  defp setup_node(name) do
    code = :code.get_path()
      |> Enum.map(&( [' -pa ', &1] ))
      |> List.flatten
    args =  code
    { :ok, node_name } = :slave.start_link(:"127.0.0.1", name, args)
    :ok = :rpc.call(node_name, :application, :start, [:elixir])
    node_name
  end

end

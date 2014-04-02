defmodule SupervisorTest do
  use ExUnit.Case, async: true

  defmodule Stack do
    use GenServer

    def start_link(state) do
      GenServer.start_link(__MODULE__, state, [local: :sup_stack])
    end

    def handle_call(:pop, _from, [h|t]) do
      { :reply, h, t }
    end

    def handle_call(:stop, _from, stack) do
      { :stop, :normal, :ok, stack }
    end

    def handle_cast({ :push, h }, _from, t) do
      { :noreply, [h|t] }
    end
  end

  import Supervisor.Spec

  test "start_link/2" do
    children = [worker(Stack, [[:hello]])]
    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

    assert GenServer.call(:sup_stack, :pop) == :hello
    assert GenServer.call(:sup_stack, :stop) == :ok

    wait_until_registered(:sup_stack)
    assert GenServer.call(:sup_stack, :pop) == :hello

    Process.exit(pid, :normal)
  end

  defp wait_until_registered(name) do
    unless Process.whereis(name) do
      wait_until_registered(name)
    end
  end
end

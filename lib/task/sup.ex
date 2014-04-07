defmodule Task.Sup do
  def start_link(opts \\ []) do
    import Supervisor.Spec
    children = [worker(Task.Supervised, [], restart: :temporary)]
    Supervisor.start_link(children, [strategy: :simple_one_for_one] ++ opts)
  end

  def async(sup_pid, fun) do
    async(sup_pid, :erlang, :apply, [fun, []])
  end

  def async(sup_pid, module, fun, args) do
    { :ok, pid } = Supervisor.start_child(sup_pid, [self(), { module, fun, args }])
    ref = Process.monitor(pid)
    send pid, { :UP, self(), ref }
    %Task{process: pid, ref: ref}
  end

  def run(sup_pid, fun) do
    run(sup_pid, :erlang, :apply, [fun, []])
  end

  def run(sup_pid, module, fun, args) do
    { :ok, _pid } = Supervisor.start_child(sup_pid, [:undefined, { module, fun, args }])
    :ok
  end
end

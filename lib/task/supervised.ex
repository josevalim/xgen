defmodule Task.Supervised do
  @moduledoc false

  def start_link(:undefined, fun) do
    :proc_lib.start_link(__MODULE__, :noreply, [fun])
  end

  def start_link(caller, fun) do
    :proc_lib.start_link(__MODULE__, :reply, [caller, fun])
  end

  def start_link(caller, fun, mon_pid, start_ref, starter) do
    :proc_lib.start_link(__MODULE__, :reply, [caller, fun, mon_pid, start_ref, starter])
  end

  def async(caller, ref, { module, fun, args }) do
    try do
      apply(module, fun, args)
    else
      result ->
        send caller, { ref, result }
    catch
      :error, reason ->
        exit({ reason, System.stacktrace() })
      :throw, value ->
        exit({ { :nocatch, value }, System.stacktrace() })
    after
      :erlang.unlink(caller)
    end
  end

  def reply(caller, mfa) do
    :erlang.link(caller)
    :proc_lib.init_ack({ :ok, self() })
    receive do: ({ ^caller, ref } -> async(caller, ref, mfa))
  end

  def reply(caller, mfa, mon_pid, start_ref, starter) do
    mon_ref = Process.monitor(starter)
    :proc_lib.init_ack({ :ok, self() })
    send(caller, { start_ref, { mon_pid, self() } })
    receive do
      # caller is monitoring with ref, continue
      { :DOWN, ^mon_ref, _, _, { ^start_ref, ref } } ->
        async(caller, ref, mfa)
      { :DOWN, ^mon_ref, _, _, reason } ->
        exit(reason)
    end
  end

  def noreply({ module, fun, args }) do
    :proc_lib.init_ack({ :ok, self() })
    try do
      apply(module, fun, args)
    catch
      :error, reason ->
        exit({ reason, System.stacktrace() })
      :throw, value ->
        exit({ { :nocatch, value }, System.stacktrace() })
    end
  end
end

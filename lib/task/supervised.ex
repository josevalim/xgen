defmodule Task.Supervised do
  @moduledoc false

  def start_link(:undefined, fun) do
    :proc_lib.start_link(__MODULE__, :noreply, [fun])
  end

  def start_link(caller, fun) do
    :proc_lib.start_link(__MODULE__, :reply, [caller, fun])
  end

  def async(caller, { module, fun, args }) do
    ref = receive do: ({ ^caller, ref } -> ref)

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
    async(caller, mfa)
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

  # Local or remote pid
  def call(pid, label, request) when is_pid(pid) do
    do_call(pid, label, request)
  end

  # Local by name
  def call(name, label, request) when is_atom(name) do
    call({ :local, name }, label, request)
  end

  # Local, global or via
  def call(process, label, request) when elem(process, 0) in [:local, :via, :global] do
    case where(process) do
      pid when is_pid(pid) ->
        do_call(pid, label, request)
      :undefined ->
        exit(:noproc)
    end
  end

  # Local by name in disguise
  def call({ name, node }, label, request) when node == node() do
    if node() == :nonode@nohost do
      exit({ :nodedown, node })
    else
      call({ :local, name }, label, request)
    end
  end

  # Remote by name
  def call({ _name, node } = process, label, request) when is_atom(node) do
    if node() == :nonode@nohost do
      exit({ :nodedown, node })
    else
      do_call(process, label, request)
    end
  end

  defp do_call(process, label, request) do
    ref = Process.monitor(process)

    try do
      # If the monitor failed to set up a connection to a remote node,
      # we don't want the send to attempt to set up the connection again
      # (if the monitor call failed due to an expired timeout, sending
      # too would probably have to wait for the timeout to expire).
      # Therefore, send/3 with the `:noconnect` option so that it will
      # fail immediately if there is no connection to the remote node.
      Process.send(process, { label, { self(), ref }, request }, [:noconnect])
    catch
      _, _ -> :ok
    end

    %Task{ref: ref, process: process}
  end

  defp where({ :global, name }),   do: :global.whereis_name(name)
  defp where({ :via, mod, name }), do: mod.whereis_name(name)
  defp where({ :local, name }),    do: :erlang.whereis(name)
end

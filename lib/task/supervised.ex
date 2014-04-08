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
end

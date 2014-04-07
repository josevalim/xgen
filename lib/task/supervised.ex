defmodule Task.Supervised do
  @moduledoc false

  def start_link(:undefined, fun) do
    :proc_lib.start_link(__MODULE__, :run, [fun])
  end

  def start_link(caller, fun) do
    :proc_lib.start_link(__MODULE__, :async, [caller, fun])
  end

  def async(caller, { module, fun, args }) do
    :erlang.link(caller)
    :proc_lib.init_ack({ :ok, self() })
    receive do
      { :UP, ^caller, ref } ->
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
  end

  def run({ module, fun, args }) do
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

defmodule ApplicationTest do
  use ExUnit.Case, async: true

  test "application environment" do
    assert Application.get_env(:elixir, :unknown) == nil
    assert Application.get_env(:elixir, :unknown, :default) == :default
    assert Application.fetch_env(:elixir, :unknown) == :error

    assert Application.put_env(:elixir, :unknown, :known) == :ok
    assert Application.fetch_env(:elixir, :unknown) == { :ok, :known }
    assert Application.get_env(:elixir, :unknown, :default) == :known

    assert Application.delete_env(:elixir, :unknown) == :ok
    assert Application.get_env(:elixir, :unknown, :default) == :default
  end

  test "application directory" do
    assert Application.app_dir(:xgen) ==
           Path.expand("../_build/test/lib/xgen", __DIR__)
    assert Application.app_dir(:xgen, "priv") ==
           Path.expand("../_build/test/lib/xgen/priv", __DIR__)

    assert_raise ArgumentError, fn ->
      Application.app_dir(:unknown)
    end
  end
end

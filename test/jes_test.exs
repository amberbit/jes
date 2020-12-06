defmodule JesTest do
  use ExUnit.Case
  doctest Jes

  test "greets the world" do
    assert Jes.hello() == :world
  end
end

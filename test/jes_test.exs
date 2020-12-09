defmodule JesTest do
  use ExUnit.Case
  doctest Jes

  test "decodes {} to empty object" do
    stream = ["{", "}"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()
    assert events == [%{key: "$", type: :object}]
  end

  test "decodes [] to empty array" do
    stream = ["[", "]"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()
    assert events == [%{key: "$", type: :array}]
  end

  test "decodes \"\" to empty string" do
    stream = ["\"", "\""] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :string, action: :start},
             %{key: "$", type: :string, action: :stop}
           ]
  end

  test "decodes a short string" do
    stream = ["\"He", "llo!\""] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :string, action: :start},
             %{key: "$", value: "Hello!"},
             %{key: "$", type: :string, action: :stop}
           ]
  end

  test "decodes true and false" do
    stream = ["tr", "ue"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :boolean},
             %{key: "$", value: true}
           ]

    stream = ["f", "alse"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :boolean},
             %{key: "$", value: false}
           ]
  end

  test "decodes zero" do
    stream = ["0"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :integer},
             %{key: "$", value: 0}
           ]

    stream = ["-0"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :integer},
             %{key: "$", value: 0}
           ]
  end

  test "decodes positive integers" do
    stream = ["123", "4", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :integer},
             %{key: "$", value: 12345}
           ]
  end

  test "decodes negative integers" do
    stream = ["-123", "4", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :integer},
             %{key: "$", value: -12345}
           ]
  end

  test "decodes positive floating point numbers" do
    stream = ["123", "4.", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: 1234.5}
           ]

    stream = ["0.123", "4", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: 0.12345}
           ]
  end

  test "decodes negative floating point numbers" do
    stream = ["-123", "4.", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: -1234.5}
           ]

    stream = ["-0.123", "4", "5"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: -0.12345}
           ]
  end

  test "decodes numbers in exponential format as floating point values" do
    stream = ["1", "e1"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: 10.0}
           ]

    stream = ["-1", "e1"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: -10.0}
           ]

    stream = ["1", "e-2"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: 0.01}
           ]

    stream = ["-", "1", "e-2"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :float},
             %{key: "$", value: -0.01}
           ]
  end

  test "decodes strings values to given max_string_chunk_size" do
    stream = ["\"", "Hello, ", "world!\""] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :string, action: :start},
             %{key: "$", value: "Hello, world!"},
             %{key: "$", type: :string, action: :stop}
           ]

    events = stream |> Jes.decode(max_string_chunk_size: 2) |> Enum.to_list()

    assert events == [
             %{key: "$", type: :string, action: :start},
             %{key: "$", value: "He"},
             %{key: "$", value: "ll"},
             %{key: "$", value: "o,"},
             %{key: "$", value: " w"},
             %{key: "$", value: "or"},
             %{key: "$", value: "ld"},
             %{key: "$", value: "!"},
             %{action: :stop, key: "$", type: :string}
           ]
  end

  test "decodes strings values to given max_string_chunk_size even breking UTF-8" do
    stream = ["\"kęs\""] |> Stream.map(& &1)

    events = stream |> Jes.decode(max_string_chunk_size: 2) |> Enum.to_list()

    assert events == [
             %{action: :start, key: "$", type: :string},
             %{key: "$", value: <<107, 196>>},
             %{key: "$", value: <<153, 115>>},
             %{action: :stop, key: "$", type: :string}
           ]

    assert <<107, 196>> <> <<153, 115>> == "kęs"
  end

  test "decodes key/value objects" do
    stream = ["{\"count", "\": 1\n,", "\t\"data\":", "\"\"\n}"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :object},
             %{key: "$.count", type: :integer},
             %{key: "$.count", value: 1},
             %{key: "$.data", type: :string, action: :start},
             %{key: "$.data", type: :string, action: :stop}
           ]
  end

  test "decodes nested objects" do
    stream = ["{", "\"payload\": {\"size\": 1}}"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :object},
             %{key: "$.payload", type: :object},
             %{key: "$.payload.size", type: :integer},
             %{key: "$.payload.size", value: 1}
           ]
  end

  # TODO: implement arrays parsing
  test "decodes arrays"

  test "stops decoding when it meets a token that shouldn't be there" do
    stream = ["{wat", "}"] |> Stream.map(& &1)
    events = stream |> Jes.decode() |> Enum.to_list()

    assert events == [
             %{key: "$", type: :object},
             %{error: "unexpected token", string: "wat}"}
           ]
  end
end

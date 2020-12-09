# Jes

Jes stands for JSON Events Stream. This is an [Elixir language](https://elixir-lang.org/) library, which
implements JSON parser that emits events into a [Stream](https://hexdocs.pm/elixir/Stream.html).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jes` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jes, "~> 0.1.0"}
  ]
end
```

## Rationale

If you work with large JSON files, having embedded large Strings in them, you may not want to decode
whole file into memory at any given time, and instead you want to process the JSON in chunks.

This library's objective is to provide you a way to do that, including also streaming chunks of Strings
that are found in JSON, so that you never have the whole JSON file loaded to the memory.

## Usage

Given that you have such file `payload.json`, you can use Jes to turn it into a Stream of
Events:

```sh
$ cat payload.json
{
  "size": 9,
	"data": "abcdefghi"
}

```

```elixir
iex> file_stream = File.stream!("payload.json")
iex> events = file_stream |> Jes.decode() |> Enum.to_list()
 %{key: "$", type: :object},
 %{key: "$.size", type: :integer},
 %{key: "$.size", value: 9},
 %{key: "$.data", type: :string, action: :start},
 %{key: "$.data", value: "abcdefghi"}
 %{key: "$.data", type: :string, action: :stop},
 ```

 Jes will stream large JSON Strings in chunks. The default chunk size is 1024 bytes. It is up to the programmer
 to concatenate them, or process in chunks. You can specify the chunk size with `max_string_chunk_size` option:

```elixir
iex> file_stream = File.stream!("payload.json")
iex> events = file_stream |> Jes.decode(max_string_chunk_size: 2) |> Enum.to_list()
 %{key: "$", type: :object},
 %{key: "$.size", type: :integer},
 %{key: "$.size", value: 1},
 %{key: "$.data", type: :string, action: :start},
 %{key: "$.data", value: "ab"},
 %{key: "$.data", value: "cd"},
 %{key: "$.data", value: "ef"},
 %{key: "$.data", value: "gh"},
 %{key: "$.data", value: "i"},
 %{key: "$.data", type: :string, action: :stop},
 ```

## Known limitations

This library is a work in progress. Currently it supports parsing simple JSON files, albeit then can be huge,
reliabiliy. The error handling is almost completely non-existent, and also there is no support for JSON array
data type just yet. Check out [GitHub Issues](https://github.com/amberbit/jes/issues) page to see what's yet
to be implemented.

The docs can be found at [https://hexdocs.pm/packages/jes](https://hexdocs.pm/packages/jes).


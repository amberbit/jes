defmodule Jes do
  @moduledoc """
  Documentation for `Jes`.
  """

  alias __MODULE__.Resource

  def decode(stream, opts \\ []) do
    max_string_chunk_size = Keyword.get(opts, :max_string_chunk_size, 1024)

    Stream.resource(
      fn ->
        {:ok, pid} =
          GenServer.start_link(Resource, [stream, max_string_chunk_size: max_string_chunk_size])

        {pid, false}
      end,
      fn
        {pid, true} ->
          {:halt, {pid, true}}

        {pid, false} ->
          events = Resource.decode_some_more(pid)

          case events do
            [] ->
              {:halt, {pid, true}}

            _ ->
              if Enum.all?(events, &(&1[:error] != nil)) do
                {events, {pid, true}}
              else
                {events, {pid, false}}
              end
          end
      end,
      fn {pid, _} -> :ok = GenServer.stop(pid) end
    )
  end
end

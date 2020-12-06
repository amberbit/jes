defmodule Jes do
  @moduledoc """
  Documentation for `Jes`.
  """

  alias __MODULE__.Resource

  def decode(stream) do
    Stream.resource(
      fn ->
        {:ok, pid} = GenServer.start_link(Resource, stream)
        pid
      end,
      fn pid ->
        events = Resource.decode_some_more(pid)

        case events do
          [] ->
            {:halt, pid}

          _ ->
            {events, pid}
        end
      end,
      fn pid -> :ok = GenServer.stop(pid) end
    )
  end
end

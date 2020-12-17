defmodule Jes.Resource do
  use GenServer

  def init([stream, max_string_chunk_size: max_string_chunk_size]) do
    {:ok,
     %{
       fun: create_suspended_stream_fun(stream),
       buffer: "",
       path: ["$"],
       mode: :expects_value,
       max_string_chunk_size: max_string_chunk_size
     }, {:continue, :fill_buffer}}
  end

  def decode_some_more(pid) do
    GenServer.call(pid, :decode_some_more)
  end

  def handle_continue(:fill_buffer, state) do
    {fun, buffer} = fill_buffer(state.fun, state.buffer, state.max_string_chunk_size)

    {:noreply, %{state | buffer: buffer, fun: fun}}
  end

  # We have reached end of input stream, meaning we're done with processing file
  # TODO: handle error when the JSON isn't correctly closed at this point.
  def handle_call(:decode_some_more, _from, %{buffer: ""} = state) do
    {:reply, [], %{state | mode: :done}}
  end

  # We have encountered error / finished before but we've been asked for more streaming.
  def handle_call(:decode_some_more, _from, %{mode: :done} = state) do
    {:reply, [], state}
  end

  # The stream should now contain a value: object, array, string, number.
  def handle_call(
        :decode_some_more,
        from,
        %{mode: :expects_value, path: path, buffer: buffer} = state
      ) do
    {events, new_path, new_mode, new_buffer} = value(buffer, path, state.max_string_chunk_size)

    GenServer.reply(from, events)

    {fun, buffer} = fill_buffer(state.fun, new_buffer, state.max_string_chunk_size)
    {:noreply, %{state | path: new_path, mode: new_mode, fun: fun, buffer: buffer}}
  end

  # The stream is within a String. Part of the stream was already sent as events,
  # but we haven't reached end of String just yet. Will emit N events, each having
  # parts of string of max_string_chunk_size tops.
  def handle_call(
        :decode_some_more,
        from,
        %{mode: :in_string, path: path, buffer: buffer} = state
      ) do
    {events, new_path, new_mode, new_buffer} =
      string(buffer, path, {"", 0}, state.max_string_chunk_size)

    GenServer.reply(from, events)

    {fun, buffer} = fill_buffer(state.fun, new_buffer, state.max_string_chunk_size)
    {:noreply, %{state | path: new_path, mode: new_mode, fun: fun, buffer: buffer}}
  end

  # We are within Object, and we expect the next thing in stream to be key,
  # or end of Object, i.e. "somekey": or }
  def handle_call(
        :decode_some_more,
        from,
        %{mode: :expects_key, path: path, buffer: buffer} = state
      ) do
    case key(buffer, path, state.max_string_chunk_size) do
      {events, _, :done, _} ->
        {:reply, events, state}

      {[], new_path, :expects_value, new_buffer} ->
        {events, new_path, new_mode, new_buffer} =
          value(new_buffer, new_path, state.max_string_chunk_size)

        GenServer.reply(from, events)

        {fun, buffer} = fill_buffer(state.fun, new_buffer, state.max_string_chunk_size)
        {:noreply, %{state | path: new_path, mode: new_mode, fun: fun, buffer: buffer}}
    end
  end

  defp key(buffer, path, max_string_chunk_size) do
    case buffer do
      <<" ", rest::bits>> ->
        key(rest, path, max_string_chunk_size)

      <<"\t", rest::bits>> ->
        key(rest, path, max_string_chunk_size)

      <<"\r", rest::bits>> ->
        key(rest, path, max_string_chunk_size)

      <<"\n", rest::bits>> ->
        key(rest, path, max_string_chunk_size)

      <<",", rest::bits>> ->
        key(rest, path, max_string_chunk_size)

      <<"\"", rest::bits>> ->
        key_name(rest, path, "")

      <<"}", _rest::bits>> ->
        {[], path, :done, ""}

      string ->
        {[%{error: "unexpected token", string: string}], path, :done, ""}
    end
  end

  defp key_name(buffer, path, name_so_far) do
    case buffer do
      <<"\"", rest::bits>> ->
        {[], path ++ [name_so_far], :expects_value, rest}

      <<c::binary-size(1), rest::bits>> ->
        key_name(rest, path, name_so_far <> c)

      _string ->
        {[%{error: "unexpected token", string: buffer}], path, :done, ""}
    end
  end

  defp value(buffer, path, max_string_chunk_size) do
    last_path_item = List.last(path)

    case buffer do
      <<" ", rest::bits>> ->
        value(rest, path, max_string_chunk_size)

      <<"\t", rest::bits>> ->
        value(rest, path, max_string_chunk_size)

      <<"\r", rest::bits>> ->
        value(rest, path, max_string_chunk_size)

      <<"\n", rest::bits>> ->
        value(rest, path, max_string_chunk_size)

      <<":", rest::bits>> ->
        value(rest, path, max_string_chunk_size)

      <<"{", rest::bits>> ->
        {[%{key: Enum.join(path, "."), type: :object}], path, :expects_key, rest}

      <<"}", _rest::bits>> ->
        {[], path, :done, ""}

      <<"[", rest::bits>> ->
        {[%{key: Enum.join(path, "."), type: :array, action: :start}], path ++ ["0"],
         :expects_value, rest}

      <<"]", rest::bits>> when last_path_item >= "0" and last_path_item <= "9" ->
        new_path = Enum.drop(path, -1)

        {[%{key: Enum.join(new_path, "."), type: :array, action: :stop}], new_path,
         :expects_value, rest}

      <<"\"", rest::bits>> ->
        {events, new_path, mode, buffer} = string(rest, path, {"", 0}, max_string_chunk_size)

        {[%{key: Enum.join(path, "."), type: :string, action: :start}] ++ events, new_path, mode,
         buffer}

      <<"true", rest::bits>> ->
        events = [
          %{key: Enum.join(path, "."), type: :boolean},
          %{key: Enum.join(path, "."), value: true}
        ]

        {new_mode, new_path} = advance_in_path(path)
        {events, new_path, new_mode, rest}

      <<"false", rest::bits>> ->
        events = [
          %{key: Enum.join(path, "."), type: :boolean},
          %{key: Enum.join(path, "."), value: false}
        ]

        {new_mode, new_path} = advance_in_path(path)
        {events, new_path, new_mode, rest}

      <<"-", rest::bits>> ->
        number(rest, path, "-")

      <<c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" ->
        number(rest, path, c)

      <<",", rest::bits>> ->
        if path |> List.last() |> String.match?(~r/^[0-9]+$/) do
          value(rest, path, max_string_chunk_size)
        else
          {[%{error: "unexpected token", string: buffer}], path, :done, ""}
        end

      _string ->
        {[%{error: "unexpected token", string: buffer}], path, :done, ""}
    end
  end

  defp number(buffer, path, number_so_far) do
    case buffer do
      <<c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" ->
        number(rest, path, number_so_far <> c)

      <<".", rest::bits>> ->
        if number_so_far |> String.contains?(".") || number_so_far |> String.contains?("e") do
          {[%{error: "unexpected token", string: buffer}], path, :done, ""}
        else
          number(rest, path, number_so_far <> ".")
        end

      <<"e", c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" ->
        number(rest, path, number_so_far <> "e" <> c)

      <<"e-", c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" ->
        number(rest, path, number_so_far <> "e-" <> c)

      <<c::binary-size(1), _rest::bits>>
      when c == "," or c == "}" or c == "]" or c == "\n" or c == "\r" or c == "\t" ->
        {type, value} = parse_number(number_so_far)
        {new_mode, new_path} = advance_in_path(path)

        {[%{key: Enum.join(path, "."), type: type}, %{key: Enum.join(path, "."), value: value}],
         new_path, new_mode, buffer}

      "" ->
        {type, value} = parse_number(number_so_far)
        {new_mode, new_path} = advance_in_path(path)

        {[%{key: Enum.join(path, "."), type: type}, %{key: Enum.join(path, "."), value: value}],
         new_path, new_mode, buffer}

      _string ->
        {[%{error: "unexpected token", string: buffer}], path, :done, ""}
    end
  end

  defp parse_number(string) do
    if String.contains?(string, ".") || String.contains?(string, "e") do
      {val, _} = Float.parse(string)
      {:float, val}
    else
      {val, _} = Integer.parse(string)
      {:integer, val}
    end
  end

  defp string(buffer, path, {string_so_far, length_so_far}, max_string_chunk_size) do
    if length_so_far >= max_string_chunk_size do
      {[%{key: Enum.join(path, "."), value: string_so_far}], path, :in_string, buffer}
    else
      case buffer do
        <<"\\\"", rest::bits>> ->
          string(rest, path, {string_so_far <> "\\\"", length_so_far + 2}, max_string_chunk_size)

        <<"\"", rest::bits>> ->
          {mode, new_path} = advance_in_path(path)

          {signal_end_of_string(%{key: Enum.join(path, "."), value: string_so_far}), new_path,
           mode, rest}

        <<c::binary-size(1), rest::bits>> ->
          string(rest, path, {string_so_far <> c, length_so_far + 1}, max_string_chunk_size)
      end
    end
  end

  defp signal_end_of_string(%{value: "", key: key}) do
    [%{key: key, type: :string, action: :stop}]
  end

  defp signal_end_of_string(%{key: key} = event) do
    [event, %{key: key, type: :string, action: :stop}]
  end

  defp advance_in_path(path) do
    last = List.last(path)

    if String.match?(last, ~r/^[0-9]+$/) do
      {:expects_value, (path |> Enum.drop(-1)) ++ ["#{String.to_integer(last) + 1}"]}
    else
      {:expects_key, path |> Enum.drop(-1)}
    end
  end

  defp create_suspended_stream_fun(stream) do
    reductor = fn item, _acc -> {:suspend, item} end
    {_, _, fun} = Enumerable.reduce(stream, {:suspend, nil}, reductor)
    fun
  end

  defp fill_buffer(nil, buffer, _), do: {nil, buffer}

  defp fill_buffer(fun, buffer, max_string_chunk_size)
       when byte_size(buffer) < max_string_chunk_size * 2 do
    {new_fun, extra_buffer} = fetch_some_bytes(fun)
    fill_buffer(new_fun, buffer <> extra_buffer, max_string_chunk_size)
  end

  defp fill_buffer(fun, buffer, _), do: {fun, buffer}

  defp fetch_some_bytes(fun) do
    fun.({:cont, nil})
    |> case do
      {:suspended, bytes, new_fun} ->
        {new_fun, bytes}

      _ ->
        {nil, ""}
    end
  end
end

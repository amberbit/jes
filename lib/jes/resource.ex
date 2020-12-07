defmodule Jes.Resource do
  use GenServer

  def init(stream) do
    {:ok, %{fun: create_suspended_stream_fun(stream), buffer: "", path: ["$"], mode: :expects_value}, {:continue, :fill_buffer}}
  end

  def decode_some_more(pid) do
    GenServer.call(pid, :decode_some_more)
  end

  def handle_continue(:fill_buffer, state) do
    {fun, buffer} = fill_buffer(state.fun, state.buffer)

    {:noreply, %{state | buffer: buffer, fun: fun}}
  end

  def handle_call(:decode_some_more, from, %{mode: :expects_value, path: path, buffer: buffer}=state) do
    {events, new_path, new_mode, new_buffer} = value(buffer, path)

    GenServer.reply(from, events)

    {fun, buffer} = fill_buffer(state.fun, new_buffer)
    {:noreply, %{state | path: new_path, mode: new_mode, fun: fun, buffer: buffer}}
  end

  def handle_call(:decode_some_more, from, %{mode: :expects_key, path: path, buffer: buffer}=state) do
    case key(buffer, path) do
      {_, _, :done, _} ->
        {:reply, [], state}

      {[], new_path, :expects_value, new_buffer} ->
        {events, new_path, new_mode, new_buffer} = value(new_buffer, new_path)
        GenServer.reply(from, events)

        {fun, buffer} = fill_buffer(state.fun, new_buffer)
        {:noreply, %{state | path: new_path, mode: new_mode, fun: fun, buffer: buffer}}
    end
  end

  defp key(buffer, path) do
    case buffer do
      <<" ", rest::bits>> -> key(rest, path)
      <<"\t", rest::bits>> -> key(rest, path)
      <<"\r", rest::bits>> -> key(rest, path)
      <<"\n", rest::bits>> -> key(rest, path)
      <<",", rest::bits>> -> key(rest, path)
      <<"\"", rest::bits>> -> key_name(rest, path, "")

      otherwise ->
        {[], path, :done, ""}
    end
  end

  defp key_name(buffer, path, name_so_far) do
    case buffer do
      <<"\"", rest::bits>> ->
        {[], path ++ [name_so_far], :expects_value, rest}
      <<c::binary-size(1), rest::bits>> ->
        key_name(rest, path, name_so_far <> c)
      otherwise ->
        {[], path, :done, ""}
    end
  end

  defp value(buffer, path) do
    case buffer do
      <<" ", rest::bits>> -> value(rest, path)
      <<"\t", rest::bits>> -> value(rest, path)
      <<"\r", rest::bits>> -> value(rest, path)
      <<"\n", rest::bits>> -> value(rest, path)
      <<":", rest::bits>> -> value(rest, path)
      <<"{", rest::bits>> ->
        {[%{key: Enum.join(path, "."), type: :object}], path, :expects_key, rest}
      <<"[", rest::bits>> ->
        {[%{key: Enum.join(path, "."), type: :array}], path ++ ["0"], :expects_value, rest}
      <<"\"", rest::bits>> ->
        {events, new_path, mode, buffer} = string(buffer, path, "")
        {[%{key: Enum.join(path, "."), type: :string}] ++ maybe_add_empty_string_event(events, path), new_path, mode, buffer}
      <<"true", rest::bits>> ->
        events = [%{key: Enum.join(path, "."), type: :boolean}, %{key: Enum.join(path, "."), value: true}]
        {new_mode, new_path} = advance_in_path(path)
        {events, new_path, new_mode, rest}

      <<"false", rest::bits>> ->
        events = [%{key: Enum.join(path, "."), type: :boolean}, %{key: Enum.join(path, "."), value: false}]
        {new_mode, new_path} = advance_in_path(path)
        {events, new_path, new_mode, rest}

      <<"-", rest::bits>> ->
        number(rest, path, "-")

      <<c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" ->
        number(rest, path, c)

      _otherwise ->
        {[], path, :done, ""}
    end
  end

  defp number(buffer, path, number_so_far) do
    case buffer do
      <<c::binary-size(1), rest::bits>> when c >= "0" and c <= "9" -> number(rest, path, number_so_far <> c)
      <<".", rest::bits>> ->
        if number_so_far |> String.contains?(".") || number_so_far |> String.contains?("e") do
          # handle error at some point, for now just stop
          {[], path, :done, ""}
        else
          number(rest, path, number_so_far <> ".")
        end
      <<"e", c::binary-size(1), rest::bits>> when  c >= "0" and c <= "9" -> number(rest, path, number_so_far <> "e" <> c)
      <<"e-", c::binary-size(1), rest::bits>> when  c >= "0" and c <= "9" -> number(rest, path, number_so_far <> "e-" <> c)
      <<c::binary-size(1), rest::bits>> when c == "," or c == "}" or c == "]" or c== "\n" or c == "\r" or c == "\t" ->
        {type, value} = parse_number(number_so_far)
        {new_mode, new_path} = advance_in_path(path)
        {[%{key: Enum.join(path, "."), type: type}, %{key: Enum.join(path, "."), value: value}], new_path, new_mode, buffer}

      "" ->
        {type, value} = parse_number(number_so_far)
        {new_mode, new_path} = advance_in_path(path)
        {[%{key: Enum.join(path, "."), type: type}, %{key: Enum.join(path, "."), value: value}], new_path, new_mode, buffer}

      _otherwise ->

        {[], path, :done, ""}
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

  defp maybe_add_empty_string_event([], path) do
    [%{key: Enum.join(path, "."), value: ""}]
  end

  defp maybe_add_empty_string_event(events, _), do: events

  defp string(buffer, path, string_so_far) do
    case buffer do
      <<"\"", rest::bits>> ->
        {mode, new_path} = advance_in_path(path)
        {[], new_path, mode, rest}
    end
  end

  defp advance_in_path(path) do
    last = List.last(path)

    if String.match?(last, ~r/^[:digit]+$/) do
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

  @min_buffer_bytes 1024

  defp fill_buffer(nil, buffer), do: {nil, buffer}

  defp fill_buffer(fun, buffer) when byte_size(buffer) < @min_buffer_bytes do
    {new_fun, extra_buffer} = fetch_some_bytes(fun)
    fill_buffer(new_fun, buffer <> extra_buffer)
  end

  defp fill_buffer(fun, buffer), do: {fun, buffer}

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

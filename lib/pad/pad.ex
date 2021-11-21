defmodule Pad.PadSupervisor do
  use Supervisor, restart: :transient

  def start_link(opts) do
    pad_id = opts |> Keyword.get(:pad_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(pad_id))
  end

  def init(opts) do
    children = [
      {Pad.PadAgent, opts},
      {Pad.PadMonitor, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def via_tuple(pad_id) do
    Pad.ProcessRegistry.via_tuple({pad_id, :supervisor})
  end
end

defmodule Pad.PadAgent do
  use Agent

  alias PadWeb.Router.Helpers, as: Routes

  @etherpad_url "https://okea.moe/etherpad/p/"

  defstruct pad_id: "",
            etherpad_url: "",
            url: "",
            pinned: false,
            created: nil,
            last_edited: nil,
            instruments: %{},
            needs: []

  def start_link(opts) do
    pad_id = opts |> Keyword.get(:pad_id)
    created = opts |> Keyword.get(:created)
    pinned = opts |> Keyword.get(:pinned)

    etherpad_url =
      URI.merge(@etherpad_url, URI.encode_www_form(pad_id))
      |> URI.to_string()

    url =
      Routes.url(PadWeb.Endpoint)
      |> URI.merge(Routes.page_path(PadWeb.Endpoint, :index, pad_id))
      |> URI.to_string()

    Agent.start_link(
      fn ->
        %__MODULE__{
          pad_id: pad_id,
          etherpad_url: etherpad_url,
          url: url,
          pinned: pinned,
          created: created
        }
      end,
      name: via_tuple(pad_id)
    )
  end

  def via_tuple(pad_id) do
    Pad.ProcessRegistry.via_tuple({pad_id, :agent})
  end

  def update(pad_id, opts) when is_binary(pad_id) do
    Pad.ProcessRegistry.lookup(pad_id, :agent)
    |> update(opts)
  end

  def update(pid, opts) do
    Agent.update(pid, &Map.merge(&1, opts))
  end

  def get(pad_id) when is_binary(pad_id) do
    Pad.ProcessRegistry.lookup(pad_id, :agent)
    |> get()
  end

  def get(pid) do
    Agent.get(pid, & &1)
  end
end

defmodule Pad.PadMonitor do
  use GenServer

  alias Pad.PadAgent

  @sleep_time 15000
  @re_sheet ~r/^(.+?) sheets: *(.+?)$/m
  @re_recording ~r/^(.+?) recording: *([^ \n].*?)$/m

  defstruct pad_id: "",
            changed: false,
            change_time: 0,
            monitor: true,
            current_text: "",
            original_text: "",
            cookies: %{},
            startup: true

  def start_link(opts) do
    pad_id = opts |> Keyword.get(:pad_id)
    monitor = opts |> Keyword.get(:monitor)
    cookies = opts |> Keyword.get(:cookies)

    GenServer.start_link(
      __MODULE__,
      %__MODULE__{cookies: cookies, pad_id: pad_id, monitor: monitor},
      name: via_tuple(pad_id)
    )
  end

  def via_tuple(room_name) do
    Pad.ProcessRegistry.via_tuple({room_name, :monitor})
  end

  def init(state) do
    if state.monitor do
      send(self(), :loop)
    end

    {:ok, state}
  end

  def handle_info(:loop, state) do
    state =
      case Pad.HTTP.get_pad_text(state, state.pad_id) do
        {%{current_text: current_text} = state, %{body: body}} ->
          body
          |> Jason.decode!()
          |> Map.get("data")
          |> Map.get("text")
          |> case do
            ^current_text ->
              if state.changed and :os.system_time(:millisecond) - state.change_time > 30000 do
                if state.original_text != current_text do
                  diff(wrap_lines(state.original_text), wrap_lines(current_text))
                  |> Enum.join("\n")
                  |> Pad.Consumer.broadcast_change(PadAgent.get(state.pad_id))
                end

                %{state | changed: false}
              else
                state
              end

            text ->
              sheets =
                Regex.scan(@re_sheet, text)
                |> Stream.map(&Enum.drop(&1, 1))
                |> Stream.map(&List.to_tuple(&1))
                |> Map.new()

              recordings =
                Regex.scan(@re_recording, text)
                |> Stream.map(&Enum.drop(&1, 1))
                |> Stream.map(&List.to_tuple(&1))
                |> Map.new()

              pad = %{
                needs: Map.keys(sheets) -- Map.keys(recordings),
                instruments:
                  Map.keys(sheets)
                  |> Stream.map(&{&1, %{sheet: sheets[&1], recording: recordings[&1]}})
                  |> Map.new()
              }

              {state, pad} =
                case Pad.HTTP.get_last_edited(state, state.pad_id) do
                  {state, %{body: body}} ->
                    {state,
                     Map.put(
                       pad,
                       :last_edited,
                       body
                       |> Jason.decode!()
                       |> Map.get("data")
                       |> Map.get("lastEdited")
                     )}

                  {state, _} ->
                    {state, pad}
                end

              PadAgent.update(state.pad_id, pad)

              cond do
                state.startup ->
                  %{state | startup: false, current_text: text}

                state.changed ->
                  %{
                    state
                    | change_time: Map.get(pad, :last_edited, :os.system_time(:millisecond)),
                      current_text: text
                  }

                true ->
                  %{
                    state
                    | changed: true,
                      original_text: current_text,
                      current_text: text,
                      change_time: Map.get(pad, :last_edited, :os.system_time(:millisecond))
                  }
              end
          end

        {state, _} ->
          state
      end

    Process.send_after(self(), :loop, @sleep_time)
    {:noreply, state}
  end

  def wrap_lines(text, max_length \\ 120) do
    text
    |> String.split("\n")
    |> Stream.map(fn line ->
      if String.length(line) > max_length do
        line
        |> Stream.unfold(&String.split_at(&1, max_length))
        |> Enum.take_while(&(&1 != ""))
      else
        [line]
      end
    end)
    |> Enum.reduce([], &(&2 ++ &1))
  end

  # Unified diff
  def diff(old_lines, new_lines, pad \\ 3)

  def diff(old_lines, new_lines, _pad) when length(old_lines) == 0 and length(new_lines) == 0 do
    []
  end

  def diff(old_lines, new_lines, _pad) when length(old_lines) == 0 and length(new_lines) != 0 do
    ["@@ 0 @@"] ++ Enum.map(new_lines, &("+" <> &1))
  end

  def diff(old_lines, new_lines, _pad) when length(old_lines) != 0 and length(new_lines) == 0 do
    ["@@ 0 @@"] ++ Enum.map(old_lines, &("-" <> &1))
  end

  def diff(old_lines, new_lines, pad) do
    {lines, index} =
      Diff.diff(old_lines, new_lines)
      |> Enum.map(fn diff ->
        case diff do
          %Diff.Modified{element: new, old_element: old, index: index, length: length} ->
            [
              %Diff.Delete{element: old, index: index, length: length},
              %Diff.Insert{element: new, index: index, length: length}
            ]

          _ ->
            [diff]
        end
      end)
      |> Enum.reduce([], &(&2 ++ &1))
      |> Enum.reduce({[], -1}, fn %{index: index} = diff, {lines, last_line} ->
        prefix =
          case diff do
            %Diff.Insert{} -> "+"
            %Diff.Delete{} -> "-"
            _ -> ""
          end

        insert = Enum.map(diff.element, &(prefix <> &1))

        pre_start =
          if index - last_line > pad do
            max(index - pad, 0)
          else
            max(max(index - pad, last_line), 0)
          end

        post_start = max(last_line, 0)

        post_lines =
          cond do
            last_line == -1 ->
              ["@@ #{index} @@"]

            last_line > -1 and index - post_start - pad > pad ->
              (new_lines
               |> Stream.drop(post_start)
               |> Enum.take(min(pad, max(pre_start - post_start, 0)))) ++
                ["@@ #{index} @@"]

            last_line > -1 and index - post_start + 1 >= pad ->
              new_lines
              |> Stream.drop(post_start)
              |> Enum.take(min(pad, max(pre_start - post_start, 0)))

            true ->
              []
          end

        pre_lines =
          new_lines
          |> Stream.drop(pre_start)
          |> Enum.take(index - pre_start)

        new_index = diff.index

        new_index =
          case diff do
            %Diff.Insert{length: len} -> new_index + len
            _ -> new_index
          end

        {lines ++ post_lines ++ pre_lines ++ insert, new_index}
      end)

    if length(new_lines) > 0 and index < length(new_lines) do
      lines ++ (Enum.drop(new_lines, index) |> Enum.take(3))
    else
      lines
    end
  end
end

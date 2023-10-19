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
            title: "",
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
          title: pad_id |> String.replace("_", " "),
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

  def get(pad_id) when is_binary(pad_id), do: Pad.ProcessRegistry.lookup(pad_id, :agent) |> get()

  def get(:not_found), do: :not_found

  def get(pid), do: Agent.get(pid, & &1)
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
      %__MODULE__{
        cookies: cookies,
        pad_id: pad_id,
        monitor: monitor
      },
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
    "[]"
  end

  def diff(old_lines, new_lines, pad) do
    Dmp.Diff.line_mode(Enum.join(old_lines, "\n"), Enum.join(new_lines, "\n"), :never)
    |> Enum.map(&[elem(&1, 0) |> to_string, elem(&1, 1)])
    |> Jason.encode!()
  end
end

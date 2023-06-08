defmodule Pad.HTTP do
  def get(url, params, state) do
    url = Application.fetch_env!(:pad, :api_url) <> url
    params = params |> Map.put(:apikey, Application.fetch_env!(:pad, :api_key))

    cookies =
      state.cookies
      |> Enum.map(fn {a, b} -> "#{a}=#{b}" end)
      |> Enum.join("; ")

    case HTTPoison.get(url, %{},
           params: params,
           hackney: [cookie: cookies]
         ) do
      {:ok, response} ->
        new_cookies =
          response.headers
          |> Enum.filter(&String.match?(elem(&1, 0), ~r/\Aset-cookie\z/i))
          |> Enum.map(fn cookie ->
            elem(cookie, 1)
            |> String.split(";")
            |> Enum.at(0)
            |> String.split("=", parts: 2)
          end)
          |> Enum.map(&List.to_tuple(&1))
          |> Map.new()

        {%{state | cookies: Map.merge(state.cookies, new_cookies)}, response}

      _ ->
        {state, nil}
    end
  end

  def get_pad_text(state, pad_id) do
    get("getText", %{padID: pad_id}, state)
  end

  def get_pads(state) do
    get("listAllPads", %{}, state)
  end

  def get_last_edited(state, pad_id) do
    get("getLastEdited", %{padID: pad_id}, state)
  end
end

defmodule Pad.Songlist do
  use GenServer

  import Ecto.Query, only: [from: 2]

  @sleep_time 5000
  @ignored_pads ["main", "start"]

  defstruct cookies: %{}, timer: nil

  def start_link(_state) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def init(state) do
    send(self(), :loop)
    {:ok, state}
  end

  def handle_cast(:loop, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    handle_info(:loop, state)
  end

  def handle_info(:loop, state) do
    state =
      case Pad.HTTP.get_pads(state) do
        {state, %{body: body}} ->
          pad_ids =
            body
            |> Jason.decode!()
            |> Map.get("data")
            |> Map.get("padIDs")

          current_pads = Pad.ProcessRegistry.get_pads()

          new_pad_ids = Enum.filter(pad_ids, &(&1 not in current_pads))
          dead_pads = current_pads -- pad_ids

          if length(new_pad_ids) > 0 do
            timestamps = get_timestamps(new_pad_ids)

            Enum.each(new_pad_ids, fn pad_id ->
              Pad.ProcessRegistry.create_pad(
                state.cookies,
                pad_id,
                timestamps[pad_id],
                pad_id in @ignored_pads,
                pad_id not in @ignored_pads
              )
            end)
          end

          Enum.each(dead_pads, fn pad_id ->
            Pad.ProcessRegistry.destroy_pad(pad_id)
          end)

          state

        {state, _} ->
          state
      end

    timer = Process.send_after(self(), :loop, @sleep_time)
    {:noreply, %{state | timer: timer}}
  end

  def handle_call(:loop, _, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    {:reply, :ok, elem(handle_info(:loop, state), 1)}
  end

  def handle_call({:create, id, text}, _, state) do
    {state, resp} = Pad.HTTP.get("createPad", %{padID: id, text: text}, state)
    {:reply, resp, state}
  end

  def handle_call({:delete, id}, _, state) do
    {state, resp} = Pad.HTTP.get("deletePad", %{padID: id}, state)
    {:reply, resp, state}
  end

  def handle_call({:get_text, pad_id}, _, state) do
    case Pad.HTTP.get_pad_text(state, pad_id) do
      {state, %{body: body}} ->
        {:reply,
         body
         |> Jason.decode!()
         |> Map.get("data")
         |> Map.get("text"), state}

      {state, _} ->
        {:reply, nil, state}
    end
  end

  def get_text(pad_id) do
    GenServer.call(__MODULE__, {:get_text, pad_id})
  end

  defp get_timestamps(pad_ids) do
    keys =
      pad_ids
      |> Enum.map(fn pad_id ->
        "pad:#{pad_id}:revs:0"
      end)

    query =
      from p in Pad.Store,
        where: p.key in ^keys,
        distinct: p.key

    Pad.Repo.all(query)
    |> Enum.map(fn x ->
      {x.key,
       Jason.decode!(x.value)
       |> Map.get("meta")
       |> Map.get("timestamp")}
    end)
    |> Enum.map(&{String.slice(elem(&1, 0), 4..-8), elem(&1, 1)})
    |> Map.new()
  end

  def create_pad(id, text, user) do
    case GenServer.call(__MODULE__, {:create, id, text}) do
      %{body: body} ->
        case Jason.decode!(body) do
          %{"message" => "ok"} ->
            Ecto.build_assoc(user, :pads)
            |> Pad.Password.changeset(%{id: id})
            |> Pad.Repo.insert()

            GenServer.call(__MODULE__, :loop)
            Pad.Consumer.broadcast_new_pad(id)
            :ok

          %{"message" => message} ->
            message
        end

      err ->
        inspect(err)
    end
  end

  def delete_pad(id) do
    case GenServer.call(__MODULE__, {:delete, id}) do
      %{body: body} ->
        case Jason.decode!(body) do
          %{"message" => "ok"} ->
            Pad.ProcessRegistry.destroy_pad(id)

            case Pad.Repo.get_by(Pad.Password, id: id) do
              nil -> :ok
              password -> Pad.Repo.delete(password)
            end

            :ok

          %{"message" => message} ->
            message
        end

      err ->
        inspect(err)
    end
  end

  def get_all_pads() do
    Pad.ProcessRegistry.get_pads()
    |> Stream.map(&(Pad.ProcessRegistry.lookup(&1, :agent) |> Pad.PadAgent.get()))
    |> Stream.map(&{&1 |> Map.get(:pad_id), &1})
    |> Map.new()
  end

  def find_pad(title) do
    title = String.downcase(title)

    Pad.ProcessRegistry.get_pads()
    |> Stream.map(& &1)
    |> Enum.sort()
    |> Enum.filter(&(String.downcase(&1) |> String.replace("_", " ") =~ title))
  end

  def get_pad(pad_id) do
    Pad.ProcessRegistry.lookup(pad_id, :agent) |> Pad.PadAgent.get()
  end

  def needs(parts) do
    get_all_pads()
    |> Stream.map(fn {_, pad} ->
      Map.merge(pad, %{
        needs:
          pad.needs
          |> Enum.filter(&(String.downcase(&1) |> String.contains?(parts))),
        original_needs: pad.needs
      })
    end)
    |> Enum.filter(&(length(&1.needs) > 0))
  end
end

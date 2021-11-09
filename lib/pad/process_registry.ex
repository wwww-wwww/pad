defmodule Pad.ProcessRegistry do
  def start_link do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  def via_tuple({room_name, key}) do
    {:via, Registry, {__MODULE__, {room_name |> String.downcase(), key}, room_name}}
  end

  def child_spec(_) do
    Supervisor.child_spec(
      Registry,
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    )
  end

  def lookup(pad_id, module) do
    case Registry.lookup(__MODULE__, {pad_id |> String.downcase(), module}) do
      [{pid, _}] -> pid
      _ -> :not_found
    end
  end

  def get_pads() do
    Registry.select(__MODULE__, [{{{:"$1", :supervisor}, :"$2", :"$3"}, [], [:"$3"]}])
  end

  def create_pad(cookies, pad_id, created, pinned, monitor) do
    DynamicSupervisor.start_child(
      Pad.DynamicSupervisor,
      {Pad.PadSupervisor,
       cookies: cookies, pad_id: pad_id, created: created, pinned: pinned, monitor: monitor}
    )
  end

  def destroy_pad(pad_id) do
    DynamicSupervisor.stop(lookup(pad_id, :supervisor))
  end
end

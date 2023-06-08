defmodule PadWeb.PageController do
  use PadWeb, :controller
  alias Pad.Songlist

  def index(conn, %{"id" => id}) do
    pads = Songlist.get_all_pads()

    case Map.get(pads, id) do
      nil ->
        conn |> redirect(to: Routes.page_path(conn, :index, "main"))

      current_pad ->
        pinned_pads = pads |> Enum.filter(&elem(&1, 1).pinned)

        unpinned_pads =
          pads
          |> Enum.filter(&(not elem(&1, 1).pinned))
          |> Enum.sort_by(&elem(&1, 1).last_edited, &>=/2)

        render(conn, "index.html",
          pads: unpinned_pads,
          pinned_pads: pinned_pads,
          page: id,
          pad: current_pad,
          page_title: id |> String.replace("_", " ")
        )
    end
  end

  def index(conn, _) do
    index(conn, %{"id" => "main"})
  end
end

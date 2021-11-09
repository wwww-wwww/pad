defmodule PadWeb.PageController do
  use PadWeb, :controller
  alias Pad.Songlist

  @illegal_characters ["/", "\\", "?", "&", "#", ":", "$"]

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

  def create(%{method: "GET"} = conn, _) do
    render(conn, "create.html")
  end

  def create(%{method: "POST"} = conn, %{"name" => ""}) do
    conn
    |> put_flash(:error, "Missing title")
    |> redirect(to: Routes.page_path(conn, :create))
  end

  def create(%{method: "POST"} = conn, %{
        "name" => name,
        "password" => password,
        "inst" => insts,
        "sheet" => sheets
      }) do
    if String.contains?(name, @illegal_characters) do
      conn
      |> put_flash(:error, "Title can't have any of #{@illegal_characters |> Enum.join(", ")}")
      |> redirect(to: Routes.page_path(conn, :create))
    else
      insts
      |> Stream.with_index()
      |> Stream.filter(&(elem(&1, 0) |> String.length() > 0))
      |> Enum.map(&{elem(&1, 0), sheets |> Enum.at(elem(&1, 1))})
      |> case do
        [] ->
          conn
          |> put_flash(:error, "Missing instruments")
          |> redirect(to: Routes.page_path(conn, :create))

        instruments ->
          instruments =
            instruments
            |> Stream.map(&"#{elem(&1, 0)} sheets: #{elem(&1, 1)}\n#{elem(&1, 0)} recording: ")
            |> Enum.join("\n\n")

          text = "#{name}\n\nNotes:\n\n~~~~~~~~\n\n#{instruments}\n\n~~~~~~~~"

          case Songlist.create_pad(name, text, password) do
            :ok ->
              conn
              |> redirect(to: Routes.page_path(conn, :index, String.replace(name, " ", "_")))

            err ->
              conn
              |> put_flash(:error, err)
              |> redirect(to: Routes.page_path(conn, :create))
          end
      end
    end
  end

  def create(%{method: "POST"} = conn, %{"name" => _, "password" => _}) do
    conn
    |> put_flash(:error, "Missing instruments")
    |> redirect(to: Routes.page_path(conn, :create))
  end

  def delete(%{method: "GET"} = conn, _) do
    render(conn, "delete.html", action: :delete)
  end

  def delete(%{method: "POST"} = conn, %{"pad_id" => pad_id, "password" => password}) do
    case Pad.Repo.get_by(Pad.Password, id: pad_id) do
      nil ->
        conn
        |> put_flash(:error, "Bad paassword.")
        |> render("delete.html", action: :delete)

      %{password: hash} ->
        if Bcrypt.verify_pass(password, hash) do
          case Songlist.delete_pad(pad_id) do
            :ok ->
              conn
              |> put_flash(:info, "Pad #{pad_id} deleted.")
              |> render("delete.html", action: :delete)

            err ->
              conn
              |> put_flash(:error, err)
              |> render("delete.html", action: :delete)
          end
        else
          conn
          |> put_flash(:error, "Bad paassword.")
          |> render("delete.html", action: :delete)
        end
    end
  end

  def superdelete(%{method: "GET"} = conn, _) do
    render(conn, "delete.html", action: :superdelete)
  end

  def superdelete(%{method: "POST"} = conn, %{"pad_id" => pad_id, "password" => password}) do
    if Pad.Application.check_password(password) do
      case Songlist.delete_pad(pad_id) do
        :ok ->
          conn
          |> put_flash(:info, "Pad #{pad_id} deleted.")
          |> render("delete.html", action: :superdelete)

        err ->
          conn
          |> put_flash(:error, err)
          |> render("delete.html", action: :superdelete)
      end
    else
      conn
      |> put_flash(:error, "Bad password.")
      |> render("delete.html", action: :superdelete)
    end
  end
end

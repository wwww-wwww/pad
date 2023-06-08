defmodule PadWeb.UserController do
  use PadWeb, :controller

  alias Pad.{Accounts, Repo, User, Password, Songlist}
  alias PadWeb.UserAuth

  @illegal_characters ["/", "\\", "?", "&", "#", ":", "$"]

  def sign_in(conn, %{"username" => username, "password" => password} = user_params) do
    if user = Accounts.get_user_by_username_and_password(username, password) do
      UserAuth.log_in_user(conn, user, user_params)
    else
      conn
      |> put_flash(:error, "Incorrect username or password")
      |> redirect(to: Routes.user_path(conn, :sign_in))
    end
  end

  def sign_in(conn, _) do
    conn
    |> assign(:page_title, "Sign In")
    |> render("sign_in.html")
  end

  def sign_out(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  def sign_up(conn, %{"username" => username, "password" => password}) do
    case Accounts.register_user(%{username: username, password: password}) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        IO.inspect(changeset)

        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(inspect(value)))
            end)
          end)
          |> Enum.map(fn {k, v} -> "#{k} #{v}" end)

        conn
        |> put_flash(:error, errors |> Enum.join(", "))
        |> redirect(to: Routes.user_path(conn, :sign_up))
    end
  end

  def sign_up(conn, _) do
    conn
    |> assign(:page_title, "Sign Up")
    |> render("sign_up.html")
  end

  def user(conn, %{"username" => username}) do
    Repo.get(User, username |> String.downcase())
    |> Repo.preload(:pads)
    |> case do
      nil ->
        conn
        |> put_flash(:error, "User does not exist")
        |> redirect(to: Routes.page_path(conn, :index))

      user ->
        conn
        |> assign(:page_title, user.name)
        |> render("user.html", user: user)
    end
  end

  def change_password(conn, %{"password" => password, "new_password" => new_password}) do
    if Bcrypt.verify_pass(password, conn.assigns.current_user.password) do
      case Accounts.reset_user_password(conn.assigns.current_user, %{password: new_password}) do
        {:ok, user} ->
          conn
          |> put_flash(:info, "Password changed")
          |> put_session(
            :user_return_to,
            Routes.user_path(conn, :user, conn.assigns.current_user.username)
          )
          |> UserAuth.log_in_user(user)

        {:error, err} ->
          conn
          |> put_flash(:error, inspect(err))
          |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
      end
    else
      conn
      |> put_flash(:error, "Invalid password")
      |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
    end
  end

  def create_pad(conn, %{"name" => ""}) do
    conn
    |> put_flash(:error, "Missing title")
    |> redirect(to: Routes.user_path(conn, :create_pad))
  end

  def create_pad(conn, %{
        "name" => name,
        "inst" => insts,
        "sheet" => sheets
      }) do
    if String.contains?(name, @illegal_characters) do
      conn
      |> put_flash(:error, "Title can't have any of #{@illegal_characters |> Enum.join(", ")}")
      |> redirect(to: Routes.user_path(conn, :create_pad))
    else
      insts
      |> Stream.with_index()
      |> Stream.filter(&(elem(&1, 0) |> String.length() > 0))
      |> Enum.map(&{elem(&1, 0), sheets |> Enum.at(elem(&1, 1))})
      |> case do
        [] ->
          conn
          |> put_flash(:error, "Missing instruments")
          |> redirect(to: Routes.user_path(conn, :create_pad))

        instruments ->
          instruments =
            instruments
            |> Stream.map(&"#{elem(&1, 0)} sheets: #{elem(&1, 1)}\n#{elem(&1, 0)} recording: ")
            |> Enum.join("\n\n")

          text = "#{name}\n\nNotes:\n\n~~~~~~~~\n\n#{instruments}\n\n~~~~~~~~"

          case Songlist.create_pad(name, text, conn.assigns.current_user) do
            :ok ->
              conn
              |> redirect(to: Routes.page_path(conn, :index, String.replace(name, " ", "_")))

            err ->
              conn
              |> put_flash(:error, err)
              |> redirect(to: Routes.user_path(conn, :create_pad))
          end
      end
    end
  end

  def create_pad(conn, %{"name" => _}) do
    conn
    |> put_flash(:error, "Missing instruments")
    |> redirect(to: Routes.user_path(conn, :create_pad))
  end

  def create_pad(conn, _) do
    conn
    |> assign(:page_title, "Create Pad")
    |> render("create.html")
  end

  def claim_pad(conn, %{"pad_id" => pad_id, "password" => password}) do
    case Songlist.get_pad(pad_id) do
      :not_found ->
        conn
        |> put_flash(:error, "Pad does not exist")
        |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))

      _ ->
        Repo.get(Password, pad_id)
        |> Repo.preload(:user)
        |> case do
          nil ->
            if conn.assigns.current_user.level >= 100 do
              Ecto.build_assoc(conn.assigns.current_user, :pads)
              |> Password.changeset(%{id: pad_id})
              |> Repo.insert()

              conn
              |> put_flash(:info, "Claimed pad #{pad_id}")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
            else
              conn
              |> put_flash(:error, "Password bad or does not exist")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
            end

          %{password: hash} = pad ->
            if Bcrypt.verify_pass(password, hash) do
              Ecto.Changeset.change(pad)
              |> Ecto.Changeset.put_assoc(:user, conn.assigns.current_user)
              |> Repo.update()

              conn
              |> put_flash(:info, "Claimed pad #{pad_id}")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
            else
              conn
              |> put_flash(:error, "Password bad or does not exist")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
            end
        end
    end
  end

  def claim_pad(conn, %{"pad_id" => pad_id}) do
    claim_pad(conn, %{"pad_id" => pad_id, "password" => ""})
  end

  def delete_pad(conn, %{"pad_id" => pad_id, "confirm" => "confirm"}) do
    Repo.get(Password, pad_id)
    |> Repo.preload(:user)
    |> case do
      nil ->
        conn
        |> put_flash(:error, "Pad does not exist")
        |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))

      pad ->
        if conn.assigns.current_user.level >= 100 or
             (pad.user != nil and pad.user.username == conn.assigns.current_user.username) do
          case Songlist.delete_pad(pad_id) do
            :ok ->
              conn
              |> put_flash(:info, "Deleted pad #{pad_id}")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))

            err ->
              conn
              |> put_flash(:error, "Can't delete this pad: #{inspect(err)}")
              |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
          end
        else
          conn
          |> put_flash(:error, "Can't delete this pad!")
          |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
        end
    end
  end

  def delete_pad(conn, %{"pad_id" => pad_id}) do
    conn
    |> put_flash(:error, "Are you sure you want to do that?")
    |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
  end

  def delete_pad(conn, _) do
    conn
    |> redirect(to: Routes.user_path(conn, :user, conn.assigns.current_user.username))
  end
end

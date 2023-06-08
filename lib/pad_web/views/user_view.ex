defmodule PadWeb.UserView do
  use PadWeb, :view

  alias Pad.{Repo, Password}

  def get_password_pads() do
    Repo.all(Password)
    |> Repo.preload(:user)
  end

  def get_unpassworded_pads() do
    passworded_pads =
      get_password_pads()
      |> Enum.map(& &1.id)

    Pad.ProcessRegistry.get_pads()
    |> Kernel.--(passworded_pads)
  end
end

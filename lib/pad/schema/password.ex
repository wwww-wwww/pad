defmodule Pad.Password do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "passwords" do
    field :id, :string, primary_key: true
    field :password, :string, default: ""

    belongs_to :user, Pad.User,
      references: :username,
      foreign_key: :user_username,
      type: :string

    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:id, :password])
  end
end

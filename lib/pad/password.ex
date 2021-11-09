defmodule Pad.Password do
  use Ecto.Schema

  @primary_key false
  schema "passwords" do
    field :id, :string, primary_key: true
    field :password, :string
  end
end

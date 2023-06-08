defmodule Pad.Store do
  use Ecto.Schema

  @primary_key false
  schema "store" do
    field :key, :string
    field :value, :string
  end
end

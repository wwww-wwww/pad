defmodule Pad.Repo.Migrations.CreatePasswords do
  use Ecto.Migration

  def change do
    create table(:passwords, primary_key: false) do
      add :id, :string, primary_key: true
      add :password, :string

      timestamps()
    end
  end
end

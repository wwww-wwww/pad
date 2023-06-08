defmodule Pad.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :username, :string, primary_key: true
      add :name, :string
      add :password, :string
      add :level, :integer, default: 0

      timestamps()
    end

    create table(:users_pads, primary_key: false) do
      add :pad_id, references(:passwords, type: :string, on_delete: :delete_all)

      add :user_username,
          references(:users, column: :username, type: :string, on_delete: :delete_all)

      timestamps()
    end
  end
end

defmodule Pad.Repo.Migrations.AddPasswordsOwner do
  use Ecto.Migration

  def change do
    alter table(:passwords) do
      add :user_username,
          references(:users, column: :username, type: :string, on_delete: :delete_all)
    end
  end
end

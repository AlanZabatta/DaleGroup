defmodule DaleApp.Repo.Migrations.AddUsernameChangedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username_changed_at, :naive_datetime
    end
  end
end

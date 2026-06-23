defmodule DaleApp.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      add :requester_id, references(:users, on_delete: :delete_all), null: false
      add :addressee_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "pending"
      timestamps()
    end

    create unique_index(:friendships, [:requester_id, :addressee_id])
    create index(:friendships, [:addressee_id])
  end
end

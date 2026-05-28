defmodule DaleApp.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :type, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :brand_id, references(:brands, on_delete: :delete_all)
      add :metadata, :map

      timestamps()
    end

    create index(:events, [:user_id])
    create index(:events, [:brand_id])
    create index(:events, [:type])
  end
end

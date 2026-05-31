defmodule DaleApp.Repo.Migrations.CreateMapSaves do
  use Ecto.Migration

  def change do
    create table(:map_saves) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:map_saves, [:user_id])
    create index(:map_saves, [:brand_id])
    create unique_index(:map_saves, [:user_id, :brand_id])
  end
end

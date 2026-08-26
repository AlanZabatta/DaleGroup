defmodule DaleApp.Repo.Migrations.AgregarSedeASellThrough do
  use Ecto.Migration

  def change do
    alter table(:sell_through_snapshots) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all)
    end

    alter table(:episodios_recuperacion) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all)
    end

    create index(:sell_through_snapshots, [:brand_location_id])
    create index(:episodios_recuperacion, [:brand_location_id])
  end
end

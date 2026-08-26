defmodule DaleApp.Repo.Migrations.AgregarSedeAIncidencias do
  use Ecto.Migration

  def change do
    alter table(:incidencias_stock) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all), null: true
    end

    create index(:incidencias_stock, [:brand_location_id])
  end
end

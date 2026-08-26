defmodule DaleApp.Repo.Migrations.AgregarSedeAAsistenciasYVentas do
  use Ecto.Migration

  def change do
    alter table(:asistencias) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all), null: true
    end

    alter table(:ventas) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all), null: true
    end

    create index(:asistencias, [:brand_location_id])
    create index(:ventas, [:brand_location_id])
  end
end

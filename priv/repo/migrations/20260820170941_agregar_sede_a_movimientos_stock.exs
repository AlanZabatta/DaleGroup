defmodule DaleApp.Repo.Migrations.AgregarSedeAMovimientosStock do
  use Ecto.Migration

  def change do
    alter table(:movimientos_stock) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all)
    end

    create index(:movimientos_stock, [:brand_location_id])
  end
end

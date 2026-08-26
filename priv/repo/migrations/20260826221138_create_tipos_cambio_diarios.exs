defmodule DaleApp.Repo.Migrations.CreateTiposCambioDiarios do
  use Ecto.Migration

  def change do
    create table(:tipos_cambio_diarios) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :fecha, :date, null: false
      add :factor, :float, null: false
      add :ventas_generado, :integer, null: false, default: 0
      add :ventas_gastado, :integer, null: false, default: 0
      add :gestores_generado, :integer, null: false, default: 0
      add :gestores_gastado, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:tipos_cambio_diarios, [:brand_id, :fecha])
  end
end

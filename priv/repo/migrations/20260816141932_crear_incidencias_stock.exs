defmodule DaleApp.Repo.Migrations.CrearIncidenciasStock do
  use Ecto.Migration

  def change do
    create table(:incidencias_stock) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :codigo_talle, :string
      add :tipo, :string, null: false
      add :creado_por_user_id, :integer
      add :producto_creado_en, :naive_datetime
      add :fecha_apertura, :naive_datetime, null: false
      add :resuelta, :boolean, default: false
      add :resuelto_por_user_id, :integer
      add :fecha_resolucion, :naive_datetime
      add :puntos_otorgados, :integer

      timestamps()
    end

    create index(:incidencias_stock, [:product_id, :tipo, :resuelta])
    create index(:incidencias_stock, [:resuelto_por_user_id])
  end
end

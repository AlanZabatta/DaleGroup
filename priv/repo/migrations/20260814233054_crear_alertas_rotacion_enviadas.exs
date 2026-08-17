defmodule DaleApp.Repo.Migrations.CrearAlertasRotacionEnviadas do
  use Ecto.Migration

  def change do
    create table(:alertas_rotacion_enviadas) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :codigo_talle, :string, null: false

      timestamps()
    end

    create index(:alertas_rotacion_enviadas, [:product_id, :codigo_talle])
  end
end

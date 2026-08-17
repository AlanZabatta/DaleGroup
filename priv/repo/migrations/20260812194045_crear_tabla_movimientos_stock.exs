defmodule DaleApp.Repo.Migrations.CrearTablaMovimientosStock do
  use Ecto.Migration

  def change do
    create table(:movimientos_stock) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :tipo_accion, :string, null: false
      add :descripcion, :string, null: false
      add :producto_id, :integer
      add :producto_nombre, :string

      timestamps()
    end

    create index(:movimientos_stock, [:brand_id, :inserted_at])
  end
end

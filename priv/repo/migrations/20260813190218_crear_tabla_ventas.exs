defmodule DaleApp.Repo.Migrations.CrearTablaVentas do
  use Ecto.Migration

  def change do
    create table(:ventas) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :product_id, :integer
      add :stock_item_id, :integer
      add :producto_nombre, :string, null: false
      add :codigo_tipo, :string
      add :codigo_color, :string
      add :codigo_talle, :string
      add :precio_unitario, :integer

      timestamps()
    end

    create index(:ventas, [:brand_id, :inserted_at])
    create index(:ventas, [:codigo_tipo])
  end
end

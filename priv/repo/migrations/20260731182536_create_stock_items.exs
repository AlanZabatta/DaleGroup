defmodule DaleApp.Repo.Migrations.CreateStockItems do
  use Ecto.Migration

  def change do
    create table(:stock_items) do
      add :codigo, :string, null: false
      add :cantidad, :integer, default: 0, null: false
      add :codigo_color, :string, null: false
      add :codigo_talle, :string, null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :brand_location_id, references(:brand_locations, on_delete: :delete_all)

      timestamps()
    end

    create index(:stock_items, [:product_id])
    create index(:stock_items, [:brand_location_id])
    create unique_index(:stock_items, [:product_id, :brand_location_id, :codigo_color, :codigo_talle], name: :stock_items_unicidad_variante)
  end
end

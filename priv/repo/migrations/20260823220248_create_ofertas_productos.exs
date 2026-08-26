defmodule DaleApp.Repo.Migrations.CreateOfertasProductos do
  use Ecto.Migration

  def change do
    create table(:ofertas_productos) do
      add :tipo, :string, null: false
      add :valor, :string, null: false
      add :activa, :boolean, default: true
      add :product_id, references(:products, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:ofertas_productos, [:product_id])
  end
end

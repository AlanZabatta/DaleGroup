defmodule DaleApp.Repo.Migrations.AgregarUmbralesStockABrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :umbral_poco_stock, :integer, default: 4, null: false
      add :umbral_mucho_stock, :integer, default: 5, null: false
    end
  end
end

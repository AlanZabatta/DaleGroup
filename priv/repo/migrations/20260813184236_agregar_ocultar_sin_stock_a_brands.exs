defmodule DaleApp.Repo.Migrations.AgregarOcultarSinStockABrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :ocultar_sin_stock, :boolean, default: false, null: false
    end
  end
end

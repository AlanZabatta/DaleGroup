defmodule DaleApp.Repo.Migrations.AddOcultarInfoAdicionalABrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :ocultar_info_adicional_stock, :boolean, default: false, null: false
    end
  end
end

defmodule DaleApp.Repo.Migrations.AgregarMargenOnlineABrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :margen_online, :integer, default: 0, null: false
    end
  end
end

defmodule DaleApp.Repo.Migrations.AgregarCanalAVentas do
  use Ecto.Migration

  def change do
    alter table(:ventas) do
      add :canal, :string, default: "local", null: false
    end
  end
end

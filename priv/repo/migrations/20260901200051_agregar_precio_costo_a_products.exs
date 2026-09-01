defmodule DaleApp.Repo.Migrations.AgregarPrecioCostoAProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :precio_costo, :integer
    end
  end
end

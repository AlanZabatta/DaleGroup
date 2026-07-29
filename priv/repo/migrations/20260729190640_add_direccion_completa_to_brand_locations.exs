defmodule DaleApp.Repo.Migrations.AddDireccionCompletaToBrandLocations do
  use Ecto.Migration

  def change do
    alter table(:brand_locations) do
      add :direccion_completa, :string
    end
  end
end

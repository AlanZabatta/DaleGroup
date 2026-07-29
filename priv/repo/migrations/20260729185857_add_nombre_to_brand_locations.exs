defmodule DaleApp.Repo.Migrations.AddNombreToBrandLocations do
  use Ecto.Migration

  def change do
    alter table(:brand_locations) do
      add :nombre, :string
    end
  end
end

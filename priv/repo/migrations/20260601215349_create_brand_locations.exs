defmodule DaleApp.Repo.Migrations.CreateBrandLocations do
  use Ecto.Migration

  def change do
    create table(:brand_locations) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :address, :string
      add :latitude, :float
      add :longitude, :float

      timestamps()
    end

    create index(:brand_locations, [:brand_id])
  end
end
defmodule DaleApp.Repo.Migrations.CreateSedes do
  use Ecto.Migration

  def change do
    create table(:sedes) do
      add :nombre, :string
      add :direccion, :string
      add :latitude, :float
      add :longitude, :float
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:sedes, [:brand_id])
  end
end

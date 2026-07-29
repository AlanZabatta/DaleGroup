defmodule DaleApp.Repo.Migrations.CreateEmpleadosSedes do
  use Ecto.Migration

  def change do
    create table(:empleados_sedes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :brand_location_id, references(:brand_locations, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:empleados_sedes, [:user_id])
    create index(:empleados_sedes, [:brand_location_id])
    create unique_index(:empleados_sedes, [:user_id, :brand_location_id])
  end
end

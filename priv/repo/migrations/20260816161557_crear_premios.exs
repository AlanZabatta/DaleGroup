defmodule DaleApp.Repo.Migrations.CrearPremios do
  use Ecto.Migration

  def change do
    create table(:premios) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :nombre, :string, null: false
      add :icono, :string
      add :imagen_url, :string
      add :puntos_costo, :integer, null: false
      add :activo, :boolean, default: true

      timestamps()
    end

    create index(:premios, [:brand_id])
  end
end

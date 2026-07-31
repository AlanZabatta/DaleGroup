defmodule DaleApp.Repo.Migrations.CreateCategoriasCustom do
  use Ecto.Migration

  def change do
    create table(:categorias_custom) do
      add :nombre, :string, null: false
      add :icono, :string, null: false
      add :codigo_tipo, :string, null: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:categorias_custom, [:brand_id, :codigo_tipo])
  end
end

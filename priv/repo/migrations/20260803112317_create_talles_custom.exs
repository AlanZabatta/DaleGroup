defmodule DaleApp.Repo.Migrations.CreateTallesCustom do
  use Ecto.Migration

  def change do
    create table(:talles_custom) do
      add :nombre, :string, null: false
      add :codigo_talle, :string, null: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:talles_custom, [:brand_id, :codigo_talle])
  end
end

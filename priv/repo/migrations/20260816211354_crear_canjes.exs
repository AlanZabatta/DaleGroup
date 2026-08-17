defmodule DaleApp.Repo.Migrations.CrearCanjes do
  use Ecto.Migration

  def change do
    create table(:canjes) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :user_id, :integer, null: false
      add :premio_id, references(:premios, on_delete: :nilify_all)
      add :premio_nombre, :string, null: false
      add :puntos_costo, :integer, null: false
      add :puntos_antes, :integer
      add :puntos_despues, :integer
      add :es_dueño, :boolean, default: false

      timestamps()
    end

    create index(:canjes, [:brand_id, :user_id])
  end
end

defmodule DaleApp.Repo.Migrations.CrearComentarios do
  use Ecto.Migration

  def change do
    create table(:comentarios) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :publicacion_id, references(:publicaciones, on_delete: :delete_all), null: false
      add :contenido, :string, limit: 500, null: false
      timestamps()
    end

    create index(:comentarios, [:publicacion_id])
  end
end

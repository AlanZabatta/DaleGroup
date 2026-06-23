defmodule DaleApp.Repo.Migrations.CrearPublicaciones do
  use Ecto.Migration

  def change do
    create table(:publicaciones) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :imagen_url, :string, null: false
      add :descripcion, :string, limit: 1000
      add :likes_count, :integer, default: 0
      add :comentarios_count, :integer, default: 0

      timestamps()
    end

    create index(:publicaciones, [:user_id])
  end
end

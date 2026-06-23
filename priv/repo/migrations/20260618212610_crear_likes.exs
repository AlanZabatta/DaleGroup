defmodule DaleApp.Repo.Migrations.CrearLikes do
  use Ecto.Migration

  def change do
    create table(:likes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :publicacion_id, references(:publicaciones, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:likes, [:user_id, :publicacion_id])
  end
end

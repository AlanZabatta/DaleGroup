defmodule DaleApp.Repo.Migrations.AddLikesToComentarios do
  use Ecto.Migration

  def change do
    alter table(:comentarios) do
      add :likes_count, :integer, default: 0, null: false
    end

    create table(:comentario_likes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :comentario_id, references(:comentarios, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:comentario_likes, [:user_id, :comentario_id])
  end
end

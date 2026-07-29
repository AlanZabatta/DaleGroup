defmodule DaleApp.Repo.Migrations.CreateAsistencias do
  use Ecto.Migration

  def change do
    create table(:asistencias) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :fecha, :date, null: false
      add :hora_marcada, :time, null: false
      add :puntos, :integer, default: 0

      timestamps()
    end

    create index(:asistencias, [:brand_id])
    create index(:asistencias, [:user_id])
  end
end

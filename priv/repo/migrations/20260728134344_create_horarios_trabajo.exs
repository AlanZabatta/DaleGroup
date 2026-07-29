defmodule DaleApp.Repo.Migrations.CreateHorariosTrabajo do
  use Ecto.Migration

  def change do
    create table(:horarios_trabajo) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :nombre, :string
      add :dias, {:array, :string}, default: []
      add :tipo, :string, default: "general"
      add :hora_entrada_general, :string
      add :hora_salida_general, :string
      add :horario_por_dia, :map, default: %{}

      timestamps()
    end

    create index(:horarios_trabajo, [:brand_id])

    alter table(:users) do
      add :horario_id, references(:horarios_trabajo, on_delete: :nilify_all)
    end
  end
end

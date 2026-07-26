defmodule DaleApp.Repo.Migrations.AddSedeZonaHorarioToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sede, :string
      add :zona, :string
      add :horario_laboral, :string
    end
  end
end

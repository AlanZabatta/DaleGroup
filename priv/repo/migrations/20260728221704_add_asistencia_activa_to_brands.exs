defmodule DaleApp.Repo.Migrations.AddAsistenciaActivaToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :asistencia_activa, :boolean, default: false
    end
  end
end

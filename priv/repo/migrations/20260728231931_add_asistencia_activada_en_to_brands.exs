defmodule DaleApp.Repo.Migrations.AddAsistenciaActivadaEnToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :asistencia_activada_en, :utc_datetime
    end
  end
end

defmodule DaleApp.Repo.Migrations.AgregarEmpleadoPuntosActiva do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :empleado_puntos_activa, :boolean, default: false
      add :empleado_puntos_activada_en, :utc_datetime
    end
  end
end

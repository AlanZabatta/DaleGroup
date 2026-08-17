defmodule DaleApp.Repo.Migrations.AgregarGestionesActiva do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :gestiones_activa, :boolean, default: false
      add :gestiones_activada_en, :utc_datetime
    end
  end
end

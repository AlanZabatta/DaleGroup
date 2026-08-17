defmodule DaleApp.Repo.Migrations.AgregarVentasActiva do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :ventas_activa, :boolean, default: false
      add :ventas_activada_en, :utc_datetime
    end
  end
end

defmodule DaleApp.Repo.Migrations.AgregarNotificacionesABrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :notificaciones_seguridad_activas, :boolean, default: false, null: false
      add :notificaciones_stock_activas, :boolean, default: false, null: false
    end
  end
end

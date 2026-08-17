defmodule DaleApp.Repo.Migrations.AgregarCantidadDisponiblePremios do
  use Ecto.Migration

  def change do
    alter table(:premios) do
      add :cantidad_disponible, :integer
    end
  end
end

defmodule DaleApp.Repo.Migrations.AgregarResumenAEpisodiosRecuperacion do
  use Ecto.Migration

  def change do
    alter table(:episodios_recuperacion) do
      add :resumen_movimientos, :map, default: %{}
    end
  end
end

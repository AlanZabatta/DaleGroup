defmodule DaleApp.Repo.Migrations.AddPuntosEmpleoToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :puntos_empleo, :integer, default: 0
    end
  end
end

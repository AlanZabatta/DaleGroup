defmodule DaleApp.Repo.Migrations.AddPerfilConfigToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :perfil_config, :map, default: %{}
    end
  end
end

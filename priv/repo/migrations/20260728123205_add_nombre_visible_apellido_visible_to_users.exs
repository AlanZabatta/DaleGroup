defmodule DaleApp.Repo.Migrations.AddNombreVisibleApellidoVisibleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :nombre_visible, :string
      add :apellido_visible, :string
    end
  end
end

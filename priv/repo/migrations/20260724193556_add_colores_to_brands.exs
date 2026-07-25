defmodule DaleApp.Repo.Migrations.AddColoresToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :colores, :map, default: %{}
    end
  end
end

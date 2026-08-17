defmodule DaleApp.Repo.Migrations.AddImagesPorColorToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :images_por_color, :map, default: %{}
    end
  end
end

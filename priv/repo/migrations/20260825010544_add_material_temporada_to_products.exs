defmodule DaleApp.Repo.Migrations.AddMaterialTemporadaToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :material, {:array, :string}, default: []
      add :temporada, :string
    end
  end
end

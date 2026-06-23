defmodule DaleApp.Repo.Migrations.AddCategoriasToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :categorias, {:array, :string}, default: []
    end
  end
end

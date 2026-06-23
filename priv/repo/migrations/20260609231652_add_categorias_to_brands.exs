defmodule DaleApp.Repo.Migrations.AddCategoriasToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :categorias, {:array, :string}, default: []
    end
  end
end

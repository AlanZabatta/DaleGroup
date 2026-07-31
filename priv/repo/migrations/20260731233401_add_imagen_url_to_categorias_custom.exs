defmodule DaleApp.Repo.Migrations.AddImagenUrlToCategoriasCustom do
  use Ecto.Migration

  def change do
    alter table(:categorias_custom) do
      add :imagen_url, :string
    end
  end
end

defmodule DaleApp.Repo.Migrations.NilifyProductIdInFavorites do
  use Ecto.Migration

  def change do
    drop constraint(:favorites, "favorites_product_id_fkey")

    alter table(:favorites) do
      modify :product_id, references(:products, on_delete: :nilify_all), null: true
    end
  end
end

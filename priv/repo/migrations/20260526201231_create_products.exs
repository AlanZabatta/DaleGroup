defmodule DaleApp.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :price, :integer, null: false
      add :image, :string
      add :size, :string
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:products, [:brand_id])
  end
end

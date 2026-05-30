defmodule DaleApp.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, default: "Sin nombre"
      add :price, :integer
      add :original_price, :integer
      add :image, :string
      add :gender, :string, default: "unisex"
      add :tipo, :string
      add :position_in_brand, :integer, default: 1
      add :position_global, :integer, default: 0
      add :active, :boolean, default: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:products, [:brand_id])
    create index(:products, [:gender])
    create index(:products, [:tipo])
    create index(:products, [:position_global])
  end
end

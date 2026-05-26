defmodule DaleApp.Repo.Migrations.CreateBrandImages do
  use Ecto.Migration

  def change do
    create table(:brand_images) do
      add :url, :string, null: false
      add :order, :integer, default: 0
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:brand_images, [:brand_id])
  end
end

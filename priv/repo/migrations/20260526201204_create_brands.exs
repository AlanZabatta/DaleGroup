defmodule DaleApp.Repo.Migrations.CreateBrands do
  use Ecto.Migration

  def change do
    create table(:brands) do
      add :name, :string, null: false
      add :logo, :string
      add :description, :text
      add :address, :string
      add :latitude, :float
      add :longitude, :float
      add :image_limit, :integer, default: 10
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:brands, [:user_id])
  end
end

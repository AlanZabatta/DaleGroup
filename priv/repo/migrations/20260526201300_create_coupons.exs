defmodule DaleApp.Repo.Migrations.CreateCoupons do
  use Ecto.Migration

  def change do
    create table(:coupons) do
      add :discount, :string, null: false
      add :description, :text
      add :stock, :integer, default: 100
      add :expires_at, :utc_datetime
      add :active, :boolean, default: true
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:coupons, [:brand_id])
  end
end

defmodule DaleApp.Repo.Migrations.CreateClaims do
  use Ecto.Migration

  def change do
    create table(:claims) do
      add :code, :string, null: false
      add :status, :string, default: "pending"
      add :claimed_at, :utc_datetime
      add :redeemed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :coupon_id, references(:coupons, on_delete: :delete_all), null: false
      add :brand_id, references(:brands, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:claims, [:code])
    create index(:claims, [:user_id])
    create index(:claims, [:brand_id])
  end
end

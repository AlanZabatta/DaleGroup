defmodule DaleApp.Repo.Migrations.AddPointsAndReferralToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :points, :integer, default: 0
      add :referral_brand_id, references(:brands, on_delete: :nilify_all)
      add :is_referral, :boolean, default: false
    end
  end
end

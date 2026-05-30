defmodule DaleApp.Repo.Migrations.AddDiscountToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :discount, :integer, default: 0
    end
  end
end

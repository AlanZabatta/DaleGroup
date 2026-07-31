defmodule DaleApp.Repo.Migrations.AddPlanToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :plan, :string, default: "free", null: false
    end
  end
end

defmodule DaleApp.Repo.Migrations.AddCajeroBrandAndActiveToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :active, :boolean, default: true
    end

    alter table(:users) do
      add :cajero_brand_id, references(:brands, on_delete: :nilify_all)
    end
  end
end

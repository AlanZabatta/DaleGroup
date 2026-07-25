defmodule DaleApp.Repo.Migrations.AddAddressFullToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :address_full, :text
    end
  end
end

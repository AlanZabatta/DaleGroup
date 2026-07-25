defmodule DaleApp.Repo.Migrations.WidenBrandsAddressColumn do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      modify :address, :text
    end
  end
end

defmodule DaleApp.Repo.Migrations.AllowNullNameInBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      modify :name, :string, null: true
    end
  end
end

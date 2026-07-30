defmodule DaleApp.Repo.Migrations.AddPinHashToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :pin_hash, :string
      add :pin_visto, :boolean, default: false
    end
  end
end

defmodule DaleApp.Repo.Migrations.AddModalidadAndSlotToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :modalidad, :string, default: "presencial"
      add :featured_slot, :integer
    end
  end
end

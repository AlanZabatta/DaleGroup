defmodule DaleApp.Repo.Migrations.AddTipoMarcaToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :tipo_marca, :string, default: "normal", null: false
    end
  end
end

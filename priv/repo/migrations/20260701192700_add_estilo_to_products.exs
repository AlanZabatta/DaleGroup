defmodule DaleApp.Repo.Migrations.AddEstiloToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :estilo, :string
    end
  end
end

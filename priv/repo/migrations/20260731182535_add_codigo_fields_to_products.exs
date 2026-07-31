defmodule DaleApp.Repo.Migrations.AddCodigoFieldsToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :codigo_tipo, :string
      add :codigo_numero, :string
    end

    create index(:products, [:brand_id, :codigo_tipo, :codigo_numero])
  end
end

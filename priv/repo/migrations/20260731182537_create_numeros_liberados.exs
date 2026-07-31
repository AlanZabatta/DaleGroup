defmodule DaleApp.Repo.Migrations.CreateNumerosLiberados do
  use Ecto.Migration

  def change do
    create table(:numeros_liberados) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :codigo_tipo, :string, null: false
      add :codigo_numero, :string, null: false
      add :liberado_en, :utc_datetime, null: false

      timestamps()
    end

    create index(:numeros_liberados, [:brand_id, :codigo_tipo])
  end
end

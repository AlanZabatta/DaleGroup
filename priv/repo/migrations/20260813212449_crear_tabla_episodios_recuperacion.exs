defmodule DaleApp.Repo.Migrations.CrearTablaEpisodiosRecuperacion do
  use Ecto.Migration

  def change do
    create table(:episodios_recuperacion) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :tipo, :string, null: false
      add :sell_through_inicial, :integer, null: false
      add :sell_through_final, :integer
      add :fecha_inicio, :naive_datetime, null: false
      add :fecha_fin, :naive_datetime
      add :activo, :boolean, default: true, null: false

      timestamps()
    end

    create index(:episodios_recuperacion, [:brand_id, :tipo, :activo])

    create table(:sell_through_snapshots) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :tipo, :string, null: false
      add :porcentaje, :integer, null: false
      add :vendidas, :integer, null: false
      add :stock_actual, :integer, null: false

      timestamps()
    end

    create index(:sell_through_snapshots, [:brand_id, :tipo, :inserted_at])
  end
end

defmodule DaleApp.Repo.Migrations.AgregarSedeAMovimientosPuntos do
  use Ecto.Migration

  def change do
    # Sin esto, un movimiento de puntos no sabe de que sede salio, y el
    # ranking de Cajeros (que si filtra por sede) no puede migrarse del
    # todo a leer de aca. Nullable: no todo lo que genera puntos tiene
    # necesariamente una sede asociada (ej. asistencia general).
    alter table(:movimientos_puntos) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all)
    end

    create index(:movimientos_puntos, [:brand_location_id])
  end
end

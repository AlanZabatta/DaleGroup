defmodule DaleApp.Repo.Migrations.CreateMovimientosPuntos do
  use Ecto.Migration

  def change do
    create table(:movimientos_puntos) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # "venta" | "creacion_stock" | "incidencia" | "asistencia" | "podio"
      add :motivo, :string, null: false

      # Categoria del empleado AL MOMENTO de generar: "ventas" | "gestores".
      # Se congela: si despues cambia de rol, lo ya ganado no se recalcula.
      add :categoria, :string, null: false

      # Los tres numeros que permiten explicarle a un empleado de donde
      # salio cada punto: lo que valia la regla, por cuanto se multiplico,
      # y lo que efectivamente entro al saldo.
      add :puntos_crudos, :integer, null: false
      add :multiplicador, :float, null: false
      add :puntos_finales, :integer, null: false

      # Referencia al hecho que lo origino, para no pagar dos veces lo mismo.
      add :origen_tipo, :string
      add :origen_id, :integer

      add :fecha, :date, null: false

      timestamps()
    end

    create index(:movimientos_puntos, [:brand_id, :user_id])
    create index(:movimientos_puntos, [:brand_id, :categoria, :fecha])

    # Blindaje contra duplicados: un mismo hecho no puede generar puntos
    # dos veces, aunque el codigo lo intente por un bug o un doble click.
    create unique_index(:movimientos_puntos, [:origen_tipo, :origen_id],
             where: "origen_tipo IS NOT NULL",
             name: :movimientos_puntos_origen_unico
           )
  end
end

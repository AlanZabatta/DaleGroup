defmodule DaleApp.Repo.Migrations.AgregarSedeALogrosMensuales do
  use Ecto.Migration

  def change do
    # Sin esto, el empleado del mes era de la marca entera: un cajero de una
    # sede competia directo contra uno de otra sede con ritmos totalmente
    # distintos. Nullable porque una marca sin sedes calcula "toda la marca"
    # con brand_location_id nil, que sigue siendo un caso valido.
    alter table(:logros_mensuales) do
      add :brand_location_id, references(:brand_locations, on_delete: :nilify_all)
    end

    # El indice unico viejo (brand_id, ciclo_inicio, user_id) asumia una sola
    # fila por usuario por ciclo. Ahora un usuario puede tener una fila por
    # sede (mas una para "toda la marca" con sede nil), asi que hay que
    # sacarlo y crear el nuevo con la sede incluida.
    drop unique_index(:logros_mensuales, [:brand_id, :ciclo_inicio, :user_id],
           name: :logros_mensuales_ciclo_usuario_unico
         )

    create unique_index(:logros_mensuales, [:brand_id, :ciclo_inicio, :user_id, :brand_location_id],
             name: :logros_mensuales_ciclo_usuario_sede_unico
           )
  end
end

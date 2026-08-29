defmodule DaleApp.Repo.Migrations.AgregarSedeActivaABrands do
  use Ecto.Migration

  def change do
    # Sede que el dueño/gerente esta viendo en el editor de tienda (Mi
    # Tienda, Stock, Cajeros). Comparte una sola eleccion entre esas tres
    # pantallas en vez de que cada una tenga su propio estado suelto.
    # nil = "todas las sedes". Si la sede se borra, vuelve a nil solo.
    alter table(:brands) do
      add :sede_activa_id, references(:brand_locations, on_delete: :nilify_all)
    end
  end
end

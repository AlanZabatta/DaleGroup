defmodule DaleApp.Repo.Migrations.AgregarCategoriaALogrosMensuales do
  use Ecto.Migration

  def change do
    # La categoria del rol al momento de competir (ventas/gestores/
    # multitask), congelada — si el empleado cambia de rol despues, el
    # historial de este ciclo no debe cambiar de significado.
    alter table(:logros_mensuales) do
      add :categoria, :string
    end
  end
end

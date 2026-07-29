defmodule DaleApp.Repo.Migrations.CreateBajasEmpleados do
  use Ecto.Migration

  def change do
    create table(:bajas_empleados) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :nombre_empleado, :string
      add :email_empleado, :string
      add :razon, :string

      timestamps()
    end

    create index(:bajas_empleados, [:brand_id])
  end
end

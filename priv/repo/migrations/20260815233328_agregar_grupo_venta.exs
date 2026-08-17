defmodule DaleApp.Repo.Migrations.AgregarGrupoVenta do
  use Ecto.Migration

  def change do
    alter table(:ventas) do
      add :grupo_venta, :string
    end

    create index(:ventas, [:grupo_venta])
  end
end

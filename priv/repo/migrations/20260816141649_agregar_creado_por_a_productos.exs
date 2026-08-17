defmodule DaleApp.Repo.Migrations.AgregarCreadoPorAProductos do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :creado_por_user_id, :integer
    end

    create index(:products, [:creado_por_user_id])
  end
end

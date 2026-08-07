defmodule DaleApp.Repo.Migrations.AddUniqueConstraintCodigoProducto do
  use Ecto.Migration

  def change do
    create unique_index(:products, [:brand_id, :codigo_tipo, :codigo_numero], name: :products_codigo_unico)
  end
end

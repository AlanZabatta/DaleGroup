defmodule DaleApp.Products.MovimientoStock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "movimientos_stock" do
    field :brand_id, :id
    field :user_id, :id
    field :tipo_accion, :string
    field :descripcion, :string
    field :producto_id, :integer
    field :producto_nombre, :string

    timestamps()
  end

  def changeset(movimiento, attrs) do
    movimiento
    |> cast(attrs, [:brand_id, :user_id, :tipo_accion, :descripcion, :producto_id, :producto_nombre])
    |> validate_required([:brand_id, :tipo_accion, :descripcion])
  end
end

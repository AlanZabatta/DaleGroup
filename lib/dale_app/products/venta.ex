defmodule DaleApp.Products.Venta do
  use Ecto.Schema
  import Ecto.Changeset
  schema "ventas" do
    field :brand_id, :id
    field :user_id, :id
    field :product_id, :integer
    field :stock_item_id, :integer
    field :producto_nombre, :string
    field :codigo_tipo, :string
    field :codigo_color, :string
    field :codigo_talle, :string
    field :precio_unitario, :integer
    field :grupo_venta, :string
    field :brand_location_id, :id
    timestamps()
  end
  def changeset(venta, attrs) do
    venta
    |> cast(attrs, [:brand_id, :user_id, :product_id, :stock_item_id, :producto_nombre, :codigo_tipo, :codigo_color, :codigo_talle, :precio_unitario, :grupo_venta, :brand_location_id])
    |> validate_required([:brand_id, :producto_nombre])
  end
end

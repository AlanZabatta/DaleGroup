defmodule DaleApp.Products.AlertaRotacionEnviada do
  use Ecto.Schema
  import Ecto.Changeset

  schema "alertas_rotacion_enviadas" do
    field :codigo_talle, :string
    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :product, DaleApp.Products.Product

    timestamps()
  end

  def changeset(alerta, attrs) do
    alerta
    |> cast(attrs, [:brand_id, :product_id, :codigo_talle])
    |> validate_required([:brand_id, :product_id, :codigo_talle])
  end
end

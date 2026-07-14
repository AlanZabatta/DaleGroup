defmodule DaleApp.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string, default: "Sin nombre"
    field :price, :integer
    field :original_price, :integer
    field :image, :string
    field :gender, :string, default: "unisex"
    field :tipo, :string
    field :talles, {:array, :string}, default: []
    field :categorias, {:array, :string}, default: []
    field :estilo, :string
    field :description, :string
    field :position_in_brand, :integer, default: 1
    field :position_global, :integer, default: 0
    field :active, :boolean, default: false
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price, :original_price, :image, :gender, :tipo, :talles, :categorias, :estilo, :description, :position_in_brand, :position_global, :active, :brand_id])
    |> validate_required([:brand_id])
    |> validate_inclusion(:gender, ["hombre", "mujer", "unisex"])
  end
end

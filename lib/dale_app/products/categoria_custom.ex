defmodule DaleApp.Products.CategoriaCustom do
  use Ecto.Schema
  import Ecto.Changeset
  @iconos ~w(remera pantalon buzo campera anteojos bolso)
  schema "categorias_custom" do
    field :nombre, :string
    field :icono, :string
    field :codigo_tipo, :string
    field :imagen_url, :string
    belongs_to :brand, DaleApp.Brands.Brand
    timestamps()
  end
  def changeset(categoria, attrs) do
    categoria
    |> cast(attrs, [:nombre, :icono, :codigo_tipo, :brand_id, :imagen_url])
    |> validate_required([:nombre, :codigo_tipo, :brand_id])
    |> validate_inclusion(:icono, @iconos ++ [nil])
    |> unique_constraint([:brand_id, :codigo_tipo])
  end
  def iconos, do: @iconos
end

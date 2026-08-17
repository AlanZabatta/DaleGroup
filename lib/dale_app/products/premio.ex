defmodule DaleApp.Products.Premio do
  use Ecto.Schema
  import Ecto.Changeset

  schema "premios" do
    field :nombre, :string
    field :icono, :string
    field :imagen_url, :string
    field :puntos_costo, :integer
    field :cantidad_disponible, :integer
    field :activo, :boolean, default: true

    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(premio, attrs) do
    premio
    |> cast(attrs, [:brand_id, :nombre, :icono, :imagen_url, :puntos_costo, :activo, :cantidad_disponible])
    |> validate_required([:brand_id, :nombre, :puntos_costo])
    |> validate_number(:puntos_costo, greater_than: 0)
    |> validate_number(:cantidad_disponible, greater_than_or_equal_to: 0)
  end
end

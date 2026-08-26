defmodule DaleApp.Products.IncidenciaStock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "incidencias_stock" do
    field :codigo_talle, :string
    field :tipo, :string
    field :creado_por_user_id, :integer
    field :producto_creado_en, :naive_datetime
    field :fecha_apertura, :naive_datetime
    field :resuelta, :boolean, default: false
    field :resuelto_por_user_id, :integer
    field :fecha_resolucion, :naive_datetime
    field :puntos_otorgados, :integer

    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :product, DaleApp.Products.Product
    belongs_to :brand_location, DaleApp.Brands.BrandLocation

    timestamps()
  end

  def changeset(incidencia, attrs) do
    incidencia
    |> cast(attrs, [
      :brand_id, :product_id, :codigo_talle, :tipo, :creado_por_user_id, :producto_creado_en,
      :fecha_apertura, :resuelta, :resuelto_por_user_id, :fecha_resolucion, :puntos_otorgados,
      :brand_location_id
    ])
    |> validate_required([:brand_id, :product_id, :tipo, :fecha_apertura])
    |> validate_inclusion(:tipo, ["agotado", "talle_agotado", "poco_stock"])
  end
end

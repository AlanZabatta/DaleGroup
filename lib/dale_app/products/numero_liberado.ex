defmodule DaleApp.Products.NumeroLiberado do
  use Ecto.Schema
  import Ecto.Changeset

  schema "numeros_liberados" do
    field :codigo_tipo, :string
    field :codigo_numero, :string
    field :liberado_en, :utc_datetime
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(numero_liberado, attrs) do
    numero_liberado
    |> cast(attrs, [:codigo_tipo, :codigo_numero, :liberado_en, :brand_id])
    |> validate_required([:codigo_tipo, :codigo_numero, :liberado_en, :brand_id])
  end
end

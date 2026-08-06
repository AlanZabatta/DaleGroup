defmodule DaleApp.Products.TalleCustom do
  use Ecto.Schema
  import Ecto.Changeset

  schema "talles_custom" do
    field :nombre, :string
    field :codigo_talle, :string
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(talle, attrs) do
    talle
    |> cast(attrs, [:nombre, :codigo_talle, :brand_id])
    |> validate_required([:nombre, :codigo_talle, :brand_id])
    |> unique_constraint([:brand_id, :codigo_talle])
  end
end

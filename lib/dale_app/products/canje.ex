defmodule DaleApp.Products.Canje do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canjes" do
    field :user_id, :integer
    field :premio_nombre, :string
    field :puntos_costo, :integer
    field :puntos_antes, :integer
    field :puntos_despues, :integer
    field :es_dueño, :boolean, default: false

    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :premio, DaleApp.Products.Premio

    timestamps()
  end

  def changeset(canje, attrs) do
    canje
    |> cast(attrs, [:brand_id, :user_id, :premio_id, :premio_nombre, :puntos_costo, :puntos_antes, :puntos_despues, :es_dueño])
    |> validate_required([:brand_id, :user_id, :premio_nombre, :puntos_costo])
  end
end

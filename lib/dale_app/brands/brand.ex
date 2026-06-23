defmodule DaleApp.Brands.Brand do
  use Ecto.Schema
  import Ecto.Changeset

  schema "brands" do
    field :name, :string
    field :logo, :string
    field :cover_image, :string
    field :description, :string
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    field :image_limit, :integer, default: 12
    field :active, :boolean, default: true
    field :modalidad, :string, default: "presencial"
    field :featured_slot, :integer
    field :discount, :integer, default: 0
    field :categorias, {:array, :string}, default: []
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(brand, attrs) do
    brand
    |> cast(attrs, [:name, :logo, :cover_image, :description, :address, :latitude, :longitude, :image_limit, :active, :modalidad, :featured_slot, :user_id, :discount, :categorias])
    |> validate_required([:name, :user_id])
    |> validate_inclusion(:modalidad, ["presencial", "digital", "ambos"])
    |> validate_number(:discount, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:image_limit, [12, 14, 18, 22, 30])
  end
end

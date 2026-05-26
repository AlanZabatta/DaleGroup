defmodule DaleApp.Coupons.Coupon do
  use Ecto.Schema
  import Ecto.Changeset

  schema "coupons" do
    field :discount, :string
    field :description, :string
    field :stock, :integer, default: 100
    field :expires_at, :utc_datetime
    field :active, :boolean, default: true
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(coupon, attrs) do
    coupon
    |> cast(attrs, [:discount, :description, :stock, :expires_at, :active, :brand_id])
    |> validate_required([:discount, :brand_id])
  end
end

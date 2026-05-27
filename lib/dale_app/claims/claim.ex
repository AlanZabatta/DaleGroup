defmodule DaleApp.Claims.Claim do
  use Ecto.Schema
  import Ecto.Changeset

  schema "claims" do
    field :code, :string
    field :status, :string, default: "pending"
    field :claimed_at, :utc_datetime
    field :redeemed_at, :utc_datetime
    field :expires_at, :utc_datetime
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :coupon, DaleApp.Coupons.Coupon
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:code, :status, :claimed_at, :redeemed_at, :expires_at, :user_id, :coupon_id, :brand_id])
    |> validate_required([:code, :user_id, :coupon_id, :brand_id])
    |> unique_constraint(:code)
  end
end

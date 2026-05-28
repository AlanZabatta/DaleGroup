defmodule DaleApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string
    field :role, :string, default: "user"
    field :banned, :boolean, default: false
    field :google_id, :string
    field :points, :integer, default: 0
    field :is_referral, :boolean, default: false
    belongs_to :referral_brand, DaleApp.Brands.Brand, foreign_key: :referral_brand_id
    belongs_to :cajero_brand, DaleApp.Brands.Brand, foreign_key: :cajero_brand_id

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar, :role, :banned, :google_id, :points, :is_referral, :referral_brand_id, :cajero_brand_id])
    |> validate_required([:email])
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end
end

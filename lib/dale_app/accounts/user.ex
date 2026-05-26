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

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar, :role, :banned, :google_id])
    |> validate_required([:email])
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
  end
end

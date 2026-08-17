defmodule DaleApp.Accounts.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "push_subscriptions" do
    field :user_id, :id
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :endpoint, :p256dh, :auth])
    |> validate_required([:user_id, :endpoint, :p256dh, :auth])
    |> unique_constraint(:endpoint)
  end
end

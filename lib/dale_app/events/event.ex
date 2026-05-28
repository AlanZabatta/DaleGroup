defmodule DaleApp.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :type, :string
    field :metadata, :map
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :metadata, :user_id, :brand_id])
    |> validate_required([:type])
  end
end

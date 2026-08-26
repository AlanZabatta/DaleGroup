defmodule DaleApp.Products.SellThroughSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sell_through_snapshots" do
    field :brand_id, :id
    field :tipo, :string
    field :porcentaje, :integer
    field :vendidas, :integer
    field :stock_actual, :integer
    field :brand_location_id, :id

    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:brand_id, :tipo, :porcentaje, :vendidas, :stock_actual, :brand_location_id])
    |> validate_required([:brand_id, :tipo, :porcentaje, :vendidas, :stock_actual])
    |> validate_inclusion(:tipo, ["stock", "dale"])
  end
end

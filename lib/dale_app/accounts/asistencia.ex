defmodule DaleApp.Accounts.Asistencia do
  use Ecto.Schema
  import Ecto.Changeset
  schema "asistencias" do
    field :fecha, :date
    field :hora_marcada, :time
    field :puntos, :integer, default: 0
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :brand_location, DaleApp.Brands.BrandLocation
    timestamps()
  end
  def changeset(asistencia, attrs) do
    asistencia
    |> cast(attrs, [:fecha, :hora_marcada, :puntos, :user_id, :brand_id, :brand_location_id])
    |> validate_required([:fecha, :hora_marcada, :user_id, :brand_id])
  end
end

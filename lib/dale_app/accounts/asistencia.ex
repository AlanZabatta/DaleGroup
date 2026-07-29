defmodule DaleApp.Accounts.Asistencia do
  use Ecto.Schema
  import Ecto.Changeset

  schema "asistencias" do
    field :fecha, :date
    field :hora_marcada, :time
    field :puntos, :integer, default: 0
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(asistencia, attrs) do
    asistencia
    |> cast(attrs, [:fecha, :hora_marcada, :puntos, :user_id, :brand_id])
    |> validate_required([:fecha, :hora_marcada, :user_id, :brand_id])
  end
end

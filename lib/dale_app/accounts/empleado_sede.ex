defmodule DaleApp.Accounts.EmpleadoSede do
  use Ecto.Schema
  import Ecto.Changeset

  schema "empleados_sedes" do
    belongs_to :user, DaleApp.Accounts.User
    belongs_to :brand_location, DaleApp.Brands.BrandLocation

    timestamps()
  end

  def changeset(empleado_sede, attrs) do
    empleado_sede
    |> cast(attrs, [:user_id, :brand_location_id])
    |> validate_required([:user_id, :brand_location_id])
    |> unique_constraint([:user_id, :brand_location_id])
  end
end

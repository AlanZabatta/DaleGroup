defmodule DaleApp.Accounts.BajaEmpleado do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bajas_empleados" do
    field :nombre_empleado, :string
    field :email_empleado, :string
    field :razon, :string
    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(baja, attrs) do
    baja
    |> cast(attrs, [:nombre_empleado, :email_empleado, :razon, :brand_id])
    |> validate_required([:brand_id])
  end
end

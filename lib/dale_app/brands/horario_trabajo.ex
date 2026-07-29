defmodule DaleApp.Brands.HorarioTrabajo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "horarios_trabajo" do
    field :nombre, :string
    field :dias, {:array, :string}, default: []
    field :tipo, :string, default: "general"
    field :hora_entrada_general, :string
    field :hora_salida_general, :string
    field :horario_por_dia, :map, default: %{}
    belongs_to :brand, DaleApp.Brands.Brand
    has_many :empleados, DaleApp.Accounts.User, foreign_key: :horario_id

    timestamps()
  end

  def changeset(horario, attrs) do
    horario
    |> cast(attrs, [:nombre, :dias, :tipo, :hora_entrada_general, :hora_salida_general, :horario_por_dia, :brand_id])
    |> validate_required([:brand_id, :dias, :tipo])
  end
end

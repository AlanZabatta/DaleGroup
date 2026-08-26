defmodule DaleApp.Products.TipoCambioDiario do
  @moduledoc """
  Registro histórico del tipo de cambio Gestores->Ventas de una marca en
  un día específico. Una fila por marca por día. El `factor` ya viene
  calculado y topado (max ±10% de variación respecto al día anterior) —
  nunca se recalcula retroactivamente.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tipos_cambio_diarios" do
    field :fecha, :date
    field :factor, :float
    field :ventas_generado, :integer, default: 0
    field :ventas_gastado, :integer, default: 0
    field :gestores_generado, :integer, default: 0
    field :gestores_gastado, :integer, default: 0

    belongs_to :brand, DaleApp.Brands.Brand

    timestamps()
  end

  def changeset(registro, attrs) do
    registro
    |> cast(attrs, [
      :brand_id,
      :fecha,
      :factor,
      :ventas_generado,
      :ventas_gastado,
      :gestores_generado,
      :gestores_gastado
    ])
    |> validate_required([:brand_id, :fecha, :factor])
    |> validate_number(:factor, greater_than: 0)
    |> unique_constraint([:brand_id, :fecha])
  end
end

defmodule DaleApp.Products.MovimientoPuntos do
  @moduledoc """
  Un movimiento de puntos ganados por un empleado.

  Cada fila guarda los tres numeros que permiten explicar de donde salio
  cada punto: los crudos (lo que valia la regla), el multiplicador vigente
  ese dia, y los finales que entraron al saldo.

  Una vez escrita, la fila NO se modifica nunca. Si el multiplicador de la
  marca cambia manana, lo ya ganado queda como esta. El saldo de un
  empleado es la suma de sus movimientos menos lo que canjeo.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @motivos ~w(venta creacion_stock incidencia asistencia podio)
  @categorias ~w(ventas gestores)

  schema "movimientos_puntos" do
    field :motivo, :string
    field :categoria, :string
    field :puntos_crudos, :integer
    field :multiplicador, :float
    field :puntos_finales, :integer
    field :origen_tipo, :string
    field :origen_id, :integer
    field :fecha, :date

    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :brand_location, DaleApp.Brands.BrandLocation
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(movimiento, attrs) do
    movimiento
    |> cast(attrs, [
      :brand_id,
      :brand_location_id,
      :user_id,
      :motivo,
      :categoria,
      :puntos_crudos,
      :multiplicador,
      :puntos_finales,
      :origen_tipo,
      :origen_id,
      :fecha
    ])
    |> validate_required([
      :brand_id,
      :user_id,
      :motivo,
      :categoria,
      :puntos_crudos,
      :multiplicador,
      :puntos_finales,
      :fecha
    ])
    |> validate_inclusion(:motivo, @motivos)
    |> validate_inclusion(:categoria, @categorias)
    |> validate_number(:multiplicador, greater_than: 0)
    |> validate_number(:puntos_crudos, greater_than_or_equal_to: 0)
    |> validate_number(:puntos_finales, greater_than_or_equal_to: 0)
    |> unique_constraint([:origen_tipo, :origen_id], name: :movimientos_puntos_origen_unico)
  end
end

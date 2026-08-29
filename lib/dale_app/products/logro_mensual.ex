defmodule DaleApp.Products.LogroMensual do
  @moduledoc """
  Resultado congelado de un ciclo de 30 dias para un empleado, en una sede
  puntual (o toda la marca, si brand_location_id es nil): cuanto sumo de
  puntos de logro (posicion en su podio de categoria + posicion en el podio
  de asistencia, escala 10/8/6/4), y si quedo como ganador del ciclo EN ESA
  SEDE. Se escribe una vez por ciclo+sede cerrado y no se recalcula. Si hay
  empate en el puntaje mas alto, todos los empatados quedan con
  es_ganador: true. Si el dueno desempata a mano, esa fila pasa a
  ganador_elegido_manualmente: true y el resto de los empatados de ese
  ciclo se apagan.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "logros_mensuales" do
    field :ciclo_inicio, :date
    field :ciclo_fin, :date
    field :puntos_logro, :integer, default: 0
    field :posicion_categoria, :integer
    field :posicion_asistencia, :integer
    field :es_ganador, :boolean, default: false
    field :ganador_elegido_manualmente, :boolean, default: false

    belongs_to :brand, DaleApp.Brands.Brand
    belongs_to :brand_location, DaleApp.Brands.BrandLocation
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(logro, attrs) do
    logro
    |> cast(attrs, [
      :brand_id,
      :brand_location_id,
      :user_id,
      :ciclo_inicio,
      :ciclo_fin,
      :puntos_logro,
      :posicion_categoria,
      :posicion_asistencia,
      :es_ganador,
      :ganador_elegido_manualmente
    ])
    |> validate_required([:brand_id, :user_id, :ciclo_inicio, :ciclo_fin])
    |> validate_number(:puntos_logro, greater_than_or_equal_to: 0)
    |> unique_constraint([:brand_id, :ciclo_inicio, :user_id, :brand_location_id],
      name: :logros_mensuales_ciclo_usuario_sede_unico
    )
  end
end

defmodule DaleApp.Products.EpisodioRecuperacion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "episodios_recuperacion" do
    field :brand_id, :id
    field :tipo, :string
    field :sell_through_inicial, :integer
    field :sell_through_final, :integer
    field :fecha_inicio, :naive_datetime
    field :fecha_fin, :naive_datetime
    field :activo, :boolean, default: true
    field :resumen_movimientos, :map, default: %{}
    field :brand_location_id, :id

    timestamps()
  end

  def changeset(episodio, attrs) do
    episodio
    |> cast(attrs, [:brand_id, :tipo, :sell_through_inicial, :sell_through_final, :fecha_inicio, :fecha_fin, :activo, :resumen_movimientos, :brand_location_id])
    |> validate_required([:brand_id, :tipo, :sell_through_inicial, :fecha_inicio])
    |> validate_inclusion(:tipo, ["stock", "dale"])
  end
end

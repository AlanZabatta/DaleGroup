defmodule DaleApp.Products.OfertaProducto do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ofertas_productos" do
    field :tipo, :string
    field :valor, :string
    field :activa, :boolean, default: true
    belongs_to :product, DaleApp.Products.Product

    timestamps()
  end

  @tipos_validos ~w(cantidad porcentaje)
  @cantidades_validas ~w(2x1 3x2 3x1 4x3)

  def changeset(oferta, attrs) do
    oferta
    |> cast(attrs, [:tipo, :valor, :activa, :product_id])
    |> validate_required([:tipo, :valor, :product_id])
    |> validate_inclusion(:tipo, @tipos_validos)
    |> validate_tipo_y_valor()
  end

  defp validate_tipo_y_valor(changeset) do
    tipo = get_field(changeset, :tipo)
    valor = get_field(changeset, :valor)

    cond do
      tipo == "cantidad" and valor not in @cantidades_validas ->
        add_error(changeset, :valor, "Cantidad de oferta inválida")

      tipo == "porcentaje" ->
        case Integer.parse(to_string(valor || "")) do
          {numero, _} when numero >= 1 and numero <= 100 -> changeset
          _ -> add_error(changeset, :valor, "Ingresá un porcentaje válido")
        end

      true ->
        changeset
    end
  end
end

defmodule DaleApp.Products.StockItem do
  @moduledoc """
  Sistema DALE9: codigo interno de 9 digitos para identificar variantes de stock.

  Formato: TT CC PPP LL
    TT  = tipo de prenda (2 digitos, tabla fija)
    CC  = color (2 digitos, tabla fija)
    PPP = numero de producto dentro de ese tipo, por marca (3 digitos, se recicla a los 120 dias de baja)
    LL  = talle (2 digitos, tabla fija)

  Se puede materializar como QR (el numero tal cual) o como codigo de barras EAN-13
  (usando el prefijo 20-29 reservado para uso interno de comercios).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @tipos %{
    "01" => "Remera", "02" => "Pantalón", "03" => "Buzo", "04" => "Campera",
    "05" => "Zapatilla", "06" => "Short", "07" => "Vestido", "08" => "Camisa",
    "09" => "Falda", "10" => "Accesorio"
  }

  @colores %{
    "01" => "Negro", "02" => "Blanco", "03" => "Rojo", "04" => "Azul",
    "05" => "Verde", "06" => "Amarillo", "07" => "Gris", "08" => "Rosa",
    "09" => "Beige", "10" => "Marrón", "11" => "Naranja", "12" => "Violeta"
  }

  @talles %{
    "01" => "XS", "02" => "S", "03" => "M", "04" => "L", "05" => "XL", "06" => "XXL"
  }

  schema "stock_items" do
    field :codigo, :string
    field :cantidad, :integer, default: 0
    field :codigo_color, :string
    field :codigo_talle, :string
    belongs_to :product, DaleApp.Products.Product
    belongs_to :brand_location, DaleApp.Brands.BrandLocation

    timestamps()
  end

  def changeset(stock_item, attrs) do
    stock_item
    |> cast(attrs, [:codigo, :cantidad, :codigo_color, :codigo_talle, :product_id, :brand_location_id])
    |> validate_required([:codigo, :codigo_color, :codigo_talle, :product_id])
    |> validate_number(:cantidad, greater_than_or_equal_to: 0)
    |> unique_constraint([:product_id, :brand_location_id, :codigo_color, :codigo_talle], name: :stock_items_unicidad_variante)
  end

  def tipos, do: @tipos
  def colores, do: @colores
  def talles, do: @talles

  def nombre_tipo(codigo), do: Map.get(@tipos, codigo, "?")
  def nombre_color(codigo), do: Map.get(@colores, codigo, "?")
  def nombre_talle(codigo), do: Map.get(@talles, codigo, "?")

  @doc """
  Arma el código de 9 dígitos: tipo(2) + color(2) + producto(3) + talle(2)
  """
  def armar_codigo(codigo_tipo, codigo_color, codigo_numero_producto, codigo_talle) do
    codigo_tipo <> codigo_color <> codigo_numero_producto <> codigo_talle
  end

  @doc """
  Descompone un código de 9 dígitos en sus partes
  """
  def descomponer_codigo(codigo) when byte_size(codigo) == 9 do
    <<tipo::binary-size(2), color::binary-size(2), producto::binary-size(3), talle::binary-size(2)>> = codigo
    {:ok, %{tipo: tipo, color: color, producto: producto, talle: talle}}
  end

  def descomponer_codigo(_), do: {:error, :formato_invalido}

  @doc """
  Traduce el codigo interno de 9 digitos a un codigo de barras EAN-13
  usando el prefijo 20-29 reservado internacionalmente para uso interno
  de comercios (no requiere registro, no colisiona con codigos oficiales
  de productos de venta masiva).
  """
  def a_ean13(codigo) when byte_size(codigo) == 9 do
    base = "20" <> codigo <> "0"
    digito_control = calcular_digito_control(base)
    String.slice(base, 0, 12) <> Integer.to_string(digito_control)
  end

  defp calcular_digito_control(doce_digitos) do
    suma =
      doce_digitos
      |> String.slice(0, 12)
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digito, i}, acc ->
        peso = if rem(i, 2) == 0, do: 1, else: 3
        acc + digito * peso
      end)

    rem(10 - rem(suma, 10), 10)
  end

  @doc """
  Toma un EAN-13 generado por Dale y recupera el codigo interno de 9 digitos.
  Devuelve :error si el EAN-13 no fue generado por nuestro sistema (prefijo distinto a 20).
  """
  def desde_ean13("20" <> resto) when byte_size(resto) == 11 do
    {:ok, String.slice(resto, 0, 9)}
  end

  def desde_ean13(_), do: {:error, :no_es_codigo_dale}
end

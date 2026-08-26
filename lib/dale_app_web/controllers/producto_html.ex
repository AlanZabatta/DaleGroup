defmodule DaleAppWeb.ProductoHTML do
  use DaleAppWeb, :html
  embed_templates "producto_html/*"

  @doc """
  Formatea un precio con separador de miles estilo argentino (punto).
  Ej: 99999 -> "99.999"
  """
  def formatear_pesos(nil), do: ""

  def formatear_pesos(valor) when is_integer(valor) do
    valor
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  def formatear_pesos(valor), do: to_string(valor)
end

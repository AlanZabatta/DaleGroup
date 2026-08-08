defmodule DaleAppWeb.StockController do
  use DaleAppWeb, :controller
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.{Product, StockItem, Dale9}

  def crear_articulo(conn, params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    nombre = Map.get(params, "nombre", "Sin nombre")
    precio_original = params |> Map.get("precio_original", "0") |> String.to_integer()
    precio_final = params |> Map.get("precio_final", "0") |> String.to_integer()
    descripcion = Map.get(params, "descripcion", "")
    codigo_tipo = Map.get(params, "codigo_tipo")
    variantes_json = Map.get(params, "variantes", "{}")

    variantes =
      case Jason.decode(variantes_json) do
        {:ok, mapa} -> mapa
        _ -> %{}
      end

    cond do
      is_nil(brand) ->
        json(conn, %{ok: false, error: "Marca no encontrada"})

      is_nil(codigo_tipo) or codigo_tipo == "" ->
        json(conn, %{ok: false, error: "Falta el tipo de prenda"})

      variantes == %{} ->
        json(conn, %{ok: false, error: "No hay color/talle/cantidad cargados"})

      true ->
        grupos_por_color =
          variantes
          |> Enum.map(fn {clave, cantidad} ->
            [codigo_color, codigo_talle] = String.split(clave, "_")
            {codigo_color, codigo_talle, cantidad}
          end)
          |> Enum.group_by(fn {codigo_color, _talle, _cant} -> codigo_color end)

        resultado =
          Enum.reduce_while(grupos_por_color, {:ok, []}, fn {_codigo_color, filas}, {:ok, ids} ->
            codigo_numero = Dale9.proximo_numero(brand.id, codigo_tipo)
            count = length(DaleApp.Products.list_brand_products(brand.id))
            talles_nombres = filas |> Enum.map(fn {_c, t, _cant} -> StockItem.nombre_talle(t) end) |> Enum.uniq()

            atributos = %{
              brand_id: brand.id,
              name: nombre,
              original_price: precio_original,
              price: precio_final,
              description: descripcion,
              talles: talles_nombres,
              position_in_brand: count + 1,
              active: false,
              codigo_tipo: codigo_tipo,
              codigo_numero: codigo_numero
            }

            case DaleApp.Products.create_product(atributos) do
              {:ok, producto} ->
                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, codigo_numero, codigo_talle)

                  %StockItem{}
                  |> StockItem.changeset(%{
                    codigo: codigo,
                    cantidad: cantidad,
                    codigo_color: codigo_color,
                    codigo_talle: codigo_talle,
                    product_id: producto.id
                  })
                  |> Repo.insert()
                end)

                {:cont, {:ok, [producto.id | ids]}}

              {:error, _cambios} ->
                {:halt, {:error, ids}}
            end
          end)

        case resultado do
          {:ok, ids} -> json(conn, %{ok: true, ids: Enum.reverse(ids)})
          {:error, _ids} -> json(conn, %{ok: false, error: "Error al crear un color"})
        end
    end
  end
end

defmodule DaleAppWeb.StockController do
  use DaleAppWeb, :controller
  import Ecto.Query, only: [from: 2]
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

  def actualizar_articulo(conn, params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    nombre = Map.get(params, "nombre", "Sin nombre")
    precio_original = params |> Map.get("precio_original", "0") |> String.to_integer()
    precio_final = params |> Map.get("precio_final", "0") |> String.to_integer()
    descripcion = Map.get(params, "descripcion", "")
    codigo_tipo = Map.get(params, "codigo_tipo")
    variantes_json = Map.get(params, "variantes", "{}")
    productos_por_color_json = Map.get(params, "productos_por_color", "{}")

    variantes =
      case Jason.decode(variantes_json) do
        {:ok, mapa} -> mapa
        _ -> %{}
      end

    productos_por_color_ids =
      case Jason.decode(productos_por_color_json) do
        {:ok, mapa} -> mapa
        _ -> %{}
      end

    cond do
      is_nil(brand) ->
        json(conn, %{ok: false, error: "Marca no encontrada"})

      is_nil(codigo_tipo) or codigo_tipo == "" ->
        json(conn, %{ok: false, error: "Falta el tipo de prenda"})

      true ->
        grupos_por_color =
          variantes
          |> Enum.map(fn {clave, cantidad} ->
            [codigo_color, codigo_talle] = String.split(clave, "_")
            {codigo_color, codigo_talle, cantidad}
          end)
          |> Enum.group_by(fn {codigo_color, _talle, _cant} -> codigo_color end)

        colores_en_variantes = Map.keys(grupos_por_color)
        colores_existentes = Map.keys(productos_por_color_ids)
        colores_a_borrar = colores_existentes -- colores_en_variantes

        Enum.each(colores_a_borrar, fn codigo_color ->
          producto_id = Map.get(productos_por_color_ids, codigo_color)
          producto = Repo.get(Product, producto_id)

          if producto && producto.brand_id == brand.id do
            from(s in StockItem, where: s.product_id == ^producto.id) |> Repo.delete_all()

            if producto.codigo_tipo && producto.codigo_numero do
              Dale9.liberar_numero(brand.id, producto.codigo_tipo, producto.codigo_numero)
            end

            Repo.delete(producto)
          end
        end)

        ids_finales =
          Enum.map(grupos_por_color, fn {codigo_color, filas} ->
            producto_id_existente = Map.get(productos_por_color_ids, codigo_color)
            producto_existente = producto_id_existente && Repo.get(Product, producto_id_existente)

            producto =
              if producto_existente && producto_existente.brand_id == brand.id do
                {:ok, actualizado} =
                  DaleApp.Products.update_product(producto_existente, %{
                    name: nombre,
                    original_price: precio_original,
                    price: precio_final,
                    description: descripcion
                  })

                items_actuales =
                  from(s in StockItem, where: s.product_id == ^actualizado.id)
                  |> Repo.all()
                  |> Map.new(fn item -> {item.codigo_talle, item} end)

                talles_nuevos = Enum.map(filas, fn {_c, t, _cant} -> t end)

                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  case Map.get(items_actuales, codigo_talle) do
                    nil ->
                      codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, actualizado.codigo_numero, codigo_talle)

                      %StockItem{}
                      |> StockItem.changeset(%{
                        codigo: codigo,
                        cantidad: cantidad,
                        codigo_color: codigo_color,
                        codigo_talle: codigo_talle,
                        product_id: actualizado.id
                      })
                      |> Repo.insert()

                    item ->
                      item |> StockItem.changeset(%{cantidad: cantidad}) |> Repo.update()
                  end
                end)

                items_actuales
                |> Map.reject(fn {codigo_talle, _item} -> codigo_talle in talles_nuevos end)
                |> Enum.each(fn {_codigo_talle, item} -> Repo.delete(item) end)

                actualizado
              else
                codigo_numero = Dale9.proximo_numero(brand.id, codigo_tipo)
                count = length(DaleApp.Products.list_brand_products(brand.id))
                talles_nombres = filas |> Enum.map(fn {_c, t, _cant} -> StockItem.nombre_talle(t) end) |> Enum.uniq()

                {:ok, nuevo} =
                  DaleApp.Products.create_product(%{
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
                  })

                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, codigo_numero, codigo_talle)

                  %StockItem{}
                  |> StockItem.changeset(%{
                    codigo: codigo,
                    cantidad: cantidad,
                    codigo_color: codigo_color,
                    codigo_talle: codigo_talle,
                    product_id: nuevo.id
                  })
                  |> Repo.insert()
                end)

                nuevo
              end

            producto.id
          end)

        json(conn, %{ok: true, ids: ids_finales})
    end
  end

  def subir_imagen(conn, %{"id" => id, "imagen" => imagen}) do
    user_id = get_session(conn, :user_id)
    producto = Repo.get(Product, id)

    cond do
      is_nil(producto) ->
        json(conn, %{ok: false, error: "Producto no encontrado"})

      true ->
        brand = Repo.get(Brand, producto.brand_id)

        if brand && brand.user_id == user_id do
          imagenes_actuales = producto.images || []

          if length(imagenes_actuales) >= 3 do
            json(conn, %{ok: false, error: "Máximo 3 imágenes por producto"})
          else
            case DaleApp.Storage.upload_image(imagen.path, imagen.filename) do
              {:ok, %{body: body}} when is_map(body) ->
                guardar_imagen_stock(conn, producto, body["secure_url"], imagenes_actuales)

              {:ok, %{body: body}} when is_binary(body) ->
                case Jason.decode(body) do
                  {:ok, decoded} -> guardar_imagen_stock(conn, producto, decoded["secure_url"], imagenes_actuales)
                  _ -> json(conn, %{ok: false, error: "No se pudo procesar la respuesta de la imagen"})
                end

              _ ->
                json(conn, %{ok: false, error: "No se pudo subir la imagen, probá de nuevo"})
            end
          end
        else
          json(conn, %{ok: false})
        end
    end
  end

  defp guardar_imagen_stock(conn, _producto, nil, _imagenes_actuales) do
    json(conn, %{ok: false, error: "No se recibió la URL de la imagen"})
  end

  defp guardar_imagen_stock(conn, producto, url, imagenes_actuales) do
    nuevas_imagenes = imagenes_actuales ++ [url]
    imagen_principal = List.first(nuevas_imagenes)
    DaleApp.Products.update_product(producto, %{images: nuevas_imagenes, image: imagen_principal, active: true})
    json(conn, %{ok: true, url: url, images: nuevas_imagenes})
  end
end

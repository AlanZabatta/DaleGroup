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
    precio_costo_raw = Map.get(params, "precio_costo", "")
    precio_costo = if precio_costo_raw in ["", nil], do: nil, else: String.to_integer(precio_costo_raw)
    descripcion = Map.get(params, "descripcion", "")
    codigo_tipo = Map.get(params, "codigo_tipo")
    variantes_json = Map.get(params, "variantes", "{}")
    sedes_ids_json = Map.get(params, "sedes_ids", "[]")
    material_json = Map.get(params, "material", "[]")
    temporada_raw = Map.get(params, "temporada", "")

    oferta_activa = Map.get(params, "oferta_activa") == "true"
    oferta_attrs = %{"tipo" => Map.get(params, "oferta_tipo"), "valor" => Map.get(params, "oferta_valor")}

    variantes =
      case Jason.decode(variantes_json) do
        {:ok, mapa} -> mapa
        _ -> %{}
      end

    material =
      case Jason.decode(material_json) do
        {:ok, lista} -> lista
        _ -> []
      end

    temporada = if temporada_raw == "", do: nil, else: temporada_raw

    sedes_ids =
      case Jason.decode(sedes_ids_json) do
        {:ok, lista} -> Enum.map(lista, &String.to_integer/1)
        _ -> []
      end

    validacion_oferta =
      if oferta_activa and brand, do: DaleApp.Products.validar_oferta(brand.id, oferta_attrs), else: :ok

    cond do
      is_nil(brand) ->
        json(conn, %{ok: false, error: "Marca no encontrada"})

      is_nil(codigo_tipo) or codigo_tipo == "" ->
        json(conn, %{ok: false, error: "Falta el tipo de prenda"})

      variantes == %{} ->
        json(conn, %{ok: false, error: "No hay color/talle/cantidad cargados"})

      validacion_oferta != :ok ->
        {:error, mensaje} = validacion_oferta
        json(conn, %{ok: false, error: mensaje})

      true ->
        grupos_por_color =
          variantes
          |> Enum.map(fn {clave, cantidad} ->
            [codigo_color, codigo_talle] = String.split(clave, "_")
            {codigo_color, codigo_talle, cantidad}
          end)
          |> Enum.group_by(fn {codigo_color, _talle, _cant} -> codigo_color end)

        resultado =
          Enum.reduce_while(grupos_por_color, {:ok, []}, fn {codigo_color, filas}, {:ok, ids} ->
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
              codigo_numero: codigo_numero,
              creado_por_user_id: user_id,
              material: material,
              temporada: temporada
            }

            case DaleApp.Products.create_product(atributos) do
              {:ok, producto} ->
                DaleApp.Products.guardar_oferta_producto(producto, %{
                  "activa" => oferta_activa,
                  "tipo" => Map.get(oferta_attrs, "tipo"),
                  "valor" => Map.get(oferta_attrs, "valor")
                })

                sedes_para_crear = if sedes_ids == [], do: [nil], else: sedes_ids

                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, codigo_numero, codigo_talle)

                  Enum.each(sedes_para_crear, fn sede_id ->
                    %StockItem{}
                    |> StockItem.changeset(%{
                      codigo: codigo,
                      cantidad: cantidad,
                      codigo_color: codigo_color,
                      codigo_talle: codigo_talle,
                      product_id: producto.id,
                      brand_location_id: sede_id
                    })
                    |> Repo.insert()
                  end)
                end)

                Enum.each(sedes_para_crear, fn sede_id ->
                  DaleApp.Products.registrar_movimiento_stock(%{
                    brand_id: brand.id,
                    user_id: user_id,
                    tipo_accion: "creado",
                    descripcion: "Ha creado \"#{nombre}\"",
                    producto_id: producto.id,
                    producto_nombre: nombre,
                    brand_location_id: sede_id
                  })
                end)
                {:cont, {:ok, [{codigo_color, producto.id} | ids]}}

              {:error, _cambios} ->
                {:halt, {:error, ids}}
            end
          end)

        case resultado do
          {:ok, pares} ->
            pares = Enum.reverse(pares)

            if pares != [] do
              DaleApp.Products.NotificacionesSeguridad.revisar(%{
                brand_id: brand.id,
                user_id: user_id,
                tipo_accion: "creado",
                nombre_producto: nombre,
                precio_anterior: nil,
                precio_nuevo: nil
              })
            end

            json(conn, %{ok: true, ids: Enum.map(pares, fn {_c, id} -> id end), colores_ids: Map.new(pares)})
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
    precio_costo_raw = Map.get(params, "precio_costo", "")
    precio_costo = if precio_costo_raw in ["", nil], do: nil, else: String.to_integer(precio_costo_raw)
    descripcion = Map.get(params, "descripcion", "")
    codigo_tipo = Map.get(params, "codigo_tipo")
    variantes_json = Map.get(params, "variantes", "{}")
    productos_por_color_json = Map.get(params, "productos_por_color", "{}")
    sedes_ids_json = Map.get(params, "sedes_ids", "[]")
    material_json = Map.get(params, "material", "[]")
    temporada_raw = Map.get(params, "temporada", "")

    material =
      case Jason.decode(material_json) do
        {:ok, lista} -> lista
        _ -> []
      end

    temporada = if temporada_raw == "", do: nil, else: temporada_raw

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
    sedes_ids =
      case Jason.decode(sedes_ids_json) do
        {:ok, lista} -> Enum.map(lista, &String.to_integer/1)
        _ -> []
      end

    oferta_activa = Map.get(params, "oferta_activa") == "true"
    oferta_attrs = %{"tipo" => Map.get(params, "oferta_tipo"), "valor" => Map.get(params, "oferta_valor")}
    validacion_oferta =
      if oferta_activa and brand, do: DaleApp.Products.validar_oferta(brand.id, oferta_attrs), else: :ok

    cond do
      is_nil(brand) ->
        json(conn, %{ok: false, error: "Marca no encontrada"})

      is_nil(codigo_tipo) or codigo_tipo == "" ->
        json(conn, %{ok: false, error: "Falta el tipo de prenda"})

      validacion_oferta != :ok ->
        {:error, mensaje} = validacion_oferta
        json(conn, %{ok: false, error: mensaje})

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
            sedes_del_producto =
              from(s in StockItem, where: s.product_id == ^producto.id, select: s.brand_location_id, distinct: true)
              |> Repo.all()
            sedes_del_producto = if sedes_del_producto == [], do: [nil], else: sedes_del_producto

            from(s in StockItem, where: s.product_id == ^producto.id) |> Repo.delete_all()

            if producto.codigo_tipo && producto.codigo_numero do
              Dale9.liberar_numero(brand.id, producto.codigo_tipo, producto.codigo_numero)
            end

            Enum.each(sedes_del_producto, fn sede_id ->
              DaleApp.Products.registrar_movimiento_stock(%{
                brand_id: brand.id,
                user_id: user_id,
                tipo_accion: "eliminado",
                descripcion: "Ha eliminado \"#{producto.name}\"",
                producto_id: producto.id,
                producto_nombre: producto.name,
                brand_location_id: sede_id
              })
            end)

            Repo.delete(producto)
          end
        end)

        if colores_a_borrar != [] do
          DaleApp.Products.NotificacionesSeguridad.revisar(%{
            brand_id: brand.id,
            user_id: user_id,
            tipo_accion: "eliminado",
            nombre_producto: nombre,
            precio_anterior: nil,
            precio_nuevo: nil
          })
        end

        producto_referencia =
          productos_por_color_ids
          |> Map.values()
          |> List.first()
          |> case do
            nil -> nil
            id -> Repo.get(Product, id)
          end

        cambio_nombre = producto_referencia && producto_referencia.name != nombre
        cambio_precio = producto_referencia && producto_referencia.price != precio_final

        ids_finales =
          Enum.map(grupos_por_color, fn {codigo_color, filas} ->
            producto_id_existente = Map.get(productos_por_color_ids, codigo_color)
            producto_existente = producto_id_existente && Repo.get(Product, producto_id_existente)

            producto =
              if producto_existente && producto_existente.brand_id == brand.id do
                if producto_existente.name != nombre do
                  DaleApp.Products.registrar_movimiento_stock(%{
                    brand_id: brand.id,
                    user_id: user_id,
                    tipo_accion: "editado",
                    descripcion: "Ha cambiado el nombre de \"#{producto_existente.name}\" a \"#{nombre}\"",
                    producto_id: producto_existente.id,
                    producto_nombre: nombre
                  })
                end

                if producto_existente.price != precio_final do
                  DaleApp.Products.registrar_movimiento_stock(%{
                    brand_id: brand.id,
                    user_id: user_id,
                    tipo_accion: "editado",
                    descripcion: "Ha cambiado el precio de \"#{nombre}\" de $#{producto_existente.price} a $#{precio_final}",
                    producto_id: producto_existente.id,
                    producto_nombre: nombre
                  })
                end

                {:ok, actualizado} =
                  DaleApp.Products.update_product(producto_existente, %{
                    name: nombre,
                    original_price: precio_original,
                    price: precio_final,
                    description: descripcion,
                    material: material,
                    temporada: temporada,
                    precio_costo: precio_costo
                  })

                sedes_para_crear = if sedes_ids == [], do: [nil], else: sedes_ids

                items_actuales =
                  from(s in StockItem, where: s.product_id == ^actualizado.id)
                  |> Repo.all()
                  |> Map.new(fn item -> {{item.codigo_talle, item.brand_location_id}, item} end)

                combos_nuevos =
                  for {_c, t, _cant} <- filas, sede_id <- sedes_para_crear, do: {t, sede_id}

                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  Enum.each(sedes_para_crear, fn sede_id ->
                    case Map.get(items_actuales, {codigo_talle, sede_id}) do
                      nil ->
                        codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, actualizado.codigo_numero, codigo_talle)

                        %StockItem{}
                        |> StockItem.changeset(%{
                          codigo: codigo,
                          cantidad: cantidad,
                          codigo_color: codigo_color,
                          codigo_talle: codigo_talle,
                          product_id: actualizado.id,
                          brand_location_id: sede_id
                        })
                        |> Repo.insert()

                      item ->
                        if item.cantidad != cantidad do
                          tipo_cambio = if cantidad > item.cantidad, do: "aumentado", else: "disminuido"

                          DaleApp.Products.registrar_movimiento_stock(%{
                            brand_id: brand.id,
                            user_id: user_id,
                            tipo_accion: tipo_cambio,
                            descripcion: "Ha #{tipo_cambio} el stock de \"#{nombre}\" de #{item.cantidad} a #{cantidad}",
                            producto_id: actualizado.id,
                            producto_nombre: nombre,
                            brand_location_id: item.brand_location_id
                          })
                          DaleApp.Products.NotificacionesSeguridad.revisar(%{
                            brand_id: brand.id,
                            user_id: user_id,
                            tipo_accion: tipo_cambio,
                            nombre_producto: nombre,
                            precio_anterior: nil,
                            precio_nuevo: nil
                          })
                          DaleApp.Products.NotificacionesStock.revisar(%{
                            brand_id: brand.id,
                            user_id: user_id,
                            stock_item: item,
                            cantidad_anterior: item.cantidad,
                            cantidad_nueva: cantidad,
                            nombre_producto: nombre,
                            product_id: actualizado.id
                          })
                        end

                        item |> StockItem.changeset(%{cantidad: cantidad}) |> Repo.update()
                    end
                  end)
                end)

                items_actuales
                |> Map.reject(fn {combo, _item} -> combo in combos_nuevos end)
                |> Enum.each(fn {_combo, item} -> Repo.delete(item) end)

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
                    codigo_numero: codigo_numero,
                    creado_por_user_id: user_id,
                    material: material,
                    temporada: temporada,
                    precio_costo: precio_costo
                  })

                sedes_para_crear = if sedes_ids == [], do: [nil], else: sedes_ids

                Enum.each(filas, fn {codigo_color, codigo_talle, cantidad} ->
                  codigo = StockItem.armar_codigo(codigo_tipo, codigo_color, codigo_numero, codigo_talle)

                  Enum.each(sedes_para_crear, fn sede_id ->
                    %StockItem{}
                    |> StockItem.changeset(%{
                      codigo: codigo,
                      cantidad: cantidad,
                      codigo_color: codigo_color,
                      codigo_talle: codigo_talle,
                      product_id: nuevo.id,
                      brand_location_id: sede_id
                    })
                    |> Repo.insert()
                  end)
                end)

                nuevo
              end

            DaleApp.Products.guardar_oferta_producto(producto, %{
              "activa" => oferta_activa,
              "tipo" => Map.get(oferta_attrs, "tipo"),
              "valor" => Map.get(oferta_attrs, "valor")
            })

            {codigo_color, producto.id}
          end)

        if cambio_nombre do
          DaleApp.Products.NotificacionesSeguridad.revisar(%{
            brand_id: brand.id,
            user_id: user_id,
            tipo_accion: "editado",
            nombre_producto: nombre,
            precio_anterior: nil,
            precio_nuevo: nil
          })
        end

        if cambio_precio do
          DaleApp.Products.NotificacionesSeguridad.revisar(%{
            brand_id: brand.id,
            user_id: user_id,
            tipo_accion: "editado",
            nombre_producto: nombre,
            precio_anterior: producto_referencia.price,
            precio_nuevo: precio_final
          })
        end

        json(conn, %{
          ok: true,
          ids: Enum.map(ids_finales, fn {_c, id} -> id end),
          colores_ids: Map.new(ids_finales)
        })
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
                guardar_imagen_stock(conn, producto, body["secure_url"], imagenes_actuales, user_id)

              {:ok, %{body: body}} when is_binary(body) ->
                case Jason.decode(body) do
                  {:ok, decoded} -> guardar_imagen_stock(conn, producto, decoded["secure_url"], imagenes_actuales, user_id)
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

  defp guardar_imagen_stock(conn, _producto, nil, _imagenes_actuales, _user_id) do
    json(conn, %{ok: false, error: "No se recibió la URL de la imagen"})
  end

  defp guardar_imagen_stock(conn, producto, url, imagenes_actuales, user_id) do
    nuevas_imagenes = imagenes_actuales ++ [url]
    imagen_principal = List.first(nuevas_imagenes)
    DaleApp.Products.registrar_movimiento_stock(%{
      brand_id: producto.brand_id,
      user_id: user_id,
      tipo_accion: "editado",
      descripcion: "Ha agregado una foto a \"#{producto.name}\"",
      producto_id: producto.id,
      producto_nombre: producto.name
    })
    DaleApp.Products.NotificacionesSeguridad.revisar(%{
      brand_id: producto.brand_id,
      user_id: user_id,
      tipo_accion: "editado",
      nombre_producto: producto.name,
      precio_anterior: nil,
      precio_nuevo: nil
    })
    DaleApp.Products.update_product(producto, %{images: nuevas_imagenes, image: imagen_principal, active: true})
    json(conn, %{ok: true, url: url, images: nuevas_imagenes})
  end
end

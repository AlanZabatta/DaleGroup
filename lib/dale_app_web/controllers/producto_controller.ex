defmodule DaleAppWeb.ProductoController do
  use DaleAppWeb, :controller
  alias DaleApp.Products
  alias DaleApp.Storage
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Coupons.Coupon
  import Ecto.Query

  def index(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    productos = if brand, do: Products.list_brand_products(brand.id), else: []
    cupon = if brand, do: Repo.one(from c in Coupon, where: c.brand_id == ^brand.id and c.active == true, limit: 1), else: nil
    render(conn, :index, brand: brand, productos: productos, cupon: cupon)
  end

  def crear(conn, params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    nombre = Map.get(params, "nombre", "Sin nombre")
    precio_original = params |> Map.get("precio_original", "0") |> String.to_integer()
    precio_final = params |> Map.get("precio_final", "0") |> String.to_integer()
    descripcion = Map.get(params, "descripcion", "")
    talles = params |> Map.get("talles", "") |> String.split(",") |> Enum.reject(&(&1 == ""))
    categorias = params |> Map.get("categorias", "") |> String.split(",") |> Enum.reject(&(&1 == ""))
    count = length(Products.list_brand_products(brand.id))
    codigo_tipo = Map.get(params, "codigo_tipo")

    atributos_base = %{
      brand_id: brand.id,
      name: nombre,
      original_price: precio_original,
      price: precio_final,
      talles: talles,
      description: descripcion,
      categorias: categorias,
      position_in_brand: count + 1,
      active: false
    }

    atributos =
      if codigo_tipo && codigo_tipo != "" do
        codigo_numero = DaleApp.Products.Dale9.proximo_numero(brand.id, codigo_tipo)
        Map.merge(atributos_base, %{codigo_tipo: codigo_tipo, codigo_numero: codigo_numero})
      else
        atributos_base
      end

    case Products.create_product(atributos) do
      {:ok, product} -> json(conn, %{ok: true, id: product.id})
      {:error, _} -> json(conn, %{ok: false})
    end
  end

  def upload_imagen(conn, %{"id" => id, "imagen" => imagen}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      imagenes_actuales = product.images || []
      if length(imagenes_actuales) >= 3 do
        json(conn, %{ok: false, error: "Máximo 3 imágenes por producto"})
      else
        case Storage.upload_image(imagen.path, imagen.filename) do
          {:ok, %{body: body}} when is_map(body) ->
            procesar_url_imagen(conn, product, body["secure_url"], imagenes_actuales)
          {:ok, %{body: body}} when is_binary(body) ->
            decoded = Jason.decode!(body)
            procesar_url_imagen(conn, product, decoded["secure_url"], imagenes_actuales)
          _ ->
            if imagenes_actuales == [] do
      if product.codigo_tipo && product.codigo_numero do
        DaleApp.Products.Dale9.liberar_numero(product.brand_id, product.codigo_tipo, product.codigo_numero)
      end

      Products.delete_product(product)
            end
            json(conn, %{ok: false, error: "Upload failed"})
        end
      end
    else
      json(conn, %{ok: false})
    end
  end

  defp procesar_url_imagen(conn, product, nil, imagenes_actuales) do
    if imagenes_actuales == [] do
      Products.delete_product(product)
    end
    json(conn, %{ok: false, error: "No secure_url"})
  end

  defp procesar_url_imagen(conn, product, url, imagenes_actuales) do
    nuevas_imagenes = imagenes_actuales ++ [url]
    imagen_principal = List.first(nuevas_imagenes)
    Products.update_product(product, %{images: nuevas_imagenes, image: imagen_principal, active: true})
    json(conn, %{ok: true, url: url, images: nuevas_imagenes})
  end

  def actualizar(conn, %{"id" => id} = params) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      nombre = Map.get(params, "nombre", product.name)
      precio_original = params |> Map.get("precio_original", "0") |> String.to_integer()
      precio_final = params |> Map.get("precio_final", "0") |> String.to_integer()
      descripcion = Map.get(params, "descripcion", "")
      talles = params |> Map.get("talles", "") |> String.split(",") |> Enum.reject(&(&1 == ""))
      categorias = params |> Map.get("categorias", "") |> String.split(",") |> Enum.reject(&(&1 == ""))

      case Products.update_product(product, %{
        name: nombre,
        original_price: precio_original,
        price: precio_final,
        description: descripcion,
        talles: talles,
        categorias: categorias
      }) do
        {:ok, _} -> json(conn, %{ok: true})
        {:error, _} -> json(conn, %{ok: false})
      end
    else
      json(conn, %{ok: false})
    end
  end

  def borrar_imagen(conn, %{"id" => id, "indice" => indice}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      indice_int = String.to_integer(indice)
      imagenes_actuales = product.images || []
      nuevas_imagenes = List.delete_at(imagenes_actuales, indice_int)
      nueva_principal = List.first(nuevas_imagenes)
      Products.update_product(product, %{images: nuevas_imagenes, image: nueva_principal})
      json(conn, %{ok: true, images: nuevas_imagenes})
    else
      json(conn, %{ok: false})
    end
  end

  def borrar(conn, %{"id" => id}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      imagenes_a_borrar = (product.images || []) ++ (if product.image, do: [product.image], else: [])

      imagenes_a_borrar
      |> Enum.uniq()
      |> Enum.each(fn url -> DaleApp.Storage.delete_image(url) end)

      DaleApp.Products.IncidenciasStock.resolver_todas_de_producto(product.id, user_id)

      if creado_hoy?(product.inserted_at) do
        Repo.delete_all(
          from(m in DaleApp.Products.MovimientoStock,
            where: m.producto_id == ^product.id and m.tipo_accion == "creado"
          )
        )
      end

      Products.delete_product(product)
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end

  defp creado_hoy?(inserted_at) do
    ahora_ar = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 3600, :second)
    creado_ar = NaiveDateTime.add(inserted_at, -3 * 3600, :second)
    NaiveDateTime.to_date(ahora_ar) == NaiveDateTime.to_date(creado_ar)
  end

  defp extraer_public_id(url) when is_binary(url) do
    case Regex.run(~r{/upload/(?:v\d+/)?(.+)\.[a-zA-Z0-9]+(?:\?.*)?$}, url) do
      [_, public_id] -> public_id
      _ -> nil
    end
  end

  defp extraer_public_id(_), do: nil

  def update_nombre(conn, %{"id" => id, "nombre" => nombre}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      Products.update_product(product, %{name: nombre})
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end
  @colores_hex %{
    "Negro" => "#1a1a1a", "Blanco" => "#ffffff", "Gris" => "#9e9e9e", "Beige" => "#e8dcc8",
    "Rojo" => "#d32f2f", "Bordó" => "#6d1b1b", "Rosa" => "#e91e8c", "Naranja" => "#f57c00",
    "Amarillo" => "#fbc02d", "Verde" => "#43a047", "Verde oscuro" => "#1b5e20", "Celeste" => "#4fc3f7",
    "Azul" => "#1565c0", "Azul marino" => "#0d1b4c", "Violeta" => "#7b1fa2", "Marrón" => "#5d3a1a",
    "Dorado" => "#c9a227", "Plateado" => "#b0b0b0"
  }

  defp color_hex_por_codigo(codigo_color) do
    Map.get(@colores_hex, DaleApp.Products.StockItem.nombre_color(codigo_color), "#cccccc")
  end

  defp construir_ficha_color(p) do
    codigo_color =
      Repo.one(
        from s in DaleApp.Products.StockItem,
          where: s.product_id == ^p.id,
          select: s.codigo_color,
          limit: 1
      )

    if codigo_color do
      oferta_p = Repo.get_by(DaleApp.Products.OfertaProducto, product_id: p.id, activa: true)
      imagenes_p = (p.images && p.images != [] && p.images) || (p.image && [p.image]) || []

      %{
        product_id: p.id,
        nombre_color: DaleApp.Products.StockItem.nombre_color(codigo_color),
        hex: color_hex_por_codigo(codigo_color),
        images: imagenes_p,
        price: p.price,
        original_price: p.original_price,
        talles: p.talles || [],
        oferta:
          if oferta_p do
            %{tipo: oferta_p.tipo, valor: oferta_p.valor}
          end
      }
    end
  end

  def mostrar(conn, %{"id" => id}) do
    product = Products.get_product(id)
    brand = Repo.get(DaleApp.Brands.Brand, product.brand_id)
    user_id = get_session(conn, :user_id)
    favorito = if user_id, do: DaleApp.Favorites.favorited?(user_id, product.id), else: false
    oferta = Repo.get_by(DaleApp.Products.OfertaProducto, product_id: product.id, activa: true)

    hermanos =
      Repo.all(
        from p in DaleApp.Products.Product,
          where: p.name == ^product.name and p.brand_id == ^product.brand_id and p.active == true,
          order_by: p.id
      )

    colores =
      hermanos
      |> Enum.map(&construir_ficha_color/1)
      |> Enum.filter(& &1)

    otros_productos =
      Products.list_brand_products(brand.id)
      |> Enum.filter(&(&1.active and &1.image != nil and &1.id != product.id and &1.name != product.name))
      |> Enum.sort_by(& &1.id, :desc)
      |> Enum.take(4)

    imagenes =
      (product.images && product.images != [] && product.images) ||
        (product.image && [product.image]) || []

    render(conn, :mostrar,
      product: product,
      brand: brand,
      favorito: favorito,
      imagenes: imagenes,
      otros_productos: otros_productos,
      oferta: oferta,
      colores: colores
    )
  end

  def detalle(conn, %{"id" => id}) do
    product = Products.get_product(id)
    brand = Repo.get(DaleApp.Brands.Brand, product.brand_id)
    user_id = get_session(conn, :user_id)
    favorito = if user_id, do: DaleApp.Favorites.favorited?(user_id, product.id), else: false

    json(conn, %{
      ok: true,
      id: product.id,
      name: product.name,
      image: product.image,
      original_price: product.original_price,
      price: product.price,
      description: product.description,
      talles: product.talles || [],
      categorias: product.categorias || [],
      images: (product.images && product.images != []) && product.images || (product.image && [product.image] || []),
      brand_id: brand.id,
      brand_name: brand.name,
      favorito: favorito,
      modalidad: brand.modalidad,
      address: brand.address,
      otros_productos: Products.list_brand_products(brand.id)
        |> Enum.filter(&(&1.active and &1.image != nil and &1.id != product.id))
        |> Enum.sort_by(& &1.id, :desc)
        |> Enum.take(4)
        |> Enum.map(fn p -> %{id: p.id, image: p.image, name: p.name} end)
    })
  end

end

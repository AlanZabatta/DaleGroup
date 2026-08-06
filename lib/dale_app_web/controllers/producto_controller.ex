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
      |> Enum.each(fn url ->
        case extraer_public_id(url) do
          nil -> :ok
          public_id -> DaleApp.Storage.delete_image(public_id)
        end
      end)

      Products.delete_product(product)
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
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

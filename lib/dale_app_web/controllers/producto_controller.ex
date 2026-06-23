defmodule DaleAppWeb.ProductoController do
  use DaleAppWeb, :controller
  alias DaleApp.Products
  alias DaleApp.Storage
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def index(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    productos = if brand, do: Products.list_brand_products(brand.id), else: []
    render(conn, :index, brand: brand, productos: productos)
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
    case Products.create_product(%{
      brand_id: brand.id,
      name: nombre,
      original_price: precio_original,
      price: precio_final,
      talles: talles,
      description: descripcion,
      categorias: categorias,
      position_in_brand: count + 1,
      active: false
    }) do
      {:ok, product} -> json(conn, %{ok: true, id: product.id})
      {:error, _} -> json(conn, %{ok: false})
    end
  end

  def upload_imagen(conn, %{"id" => id, "imagen" => imagen}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      result = Storage.upload_image(imagen.path, imagen.filename)
      IO.inspect(result, label: "CLOUDINARY RESULT")
      case result do
        {:ok, %{body: body}} when is_map(body) ->
          case body["secure_url"] do
            nil ->
              IO.inspect(body, label: "CLOUDINARY ERROR BODY")
              Products.delete_product(product)
              json(conn, %{ok: false, error: "No secure_url"})
            url ->
              Products.update_product(product, %{image: url, active: true})
              json(conn, %{ok: true, url: url})
          end
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          IO.inspect(decoded, label: "CLOUDINARY DECODED")
          case decoded["secure_url"] do
            nil -> Products.delete_product(product)
              json(conn, %{ok: false, error: "No secure_url"})
            url ->
              Products.update_product(product, %{image: url, active: true})
              json(conn, %{ok: true, url: url})
          end
        other ->
          IO.inspect(other, label: "CLOUDINARY OTHER")
          Products.delete_product(product)
          json(conn, %{ok: false, error: "Upload failed"})
      end
    else
      json(conn, %{ok: false})
    end
  end

  def borrar(conn, %{"id" => id}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = Repo.get(Brand, product.brand_id)
    if brand.user_id == user_id do
      Products.delete_product(product)
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end

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

defmodule DaleAppWeb.ProductoController do
  use DaleAppWeb, :controller
  alias DaleApp.Products
  alias DaleApp.Storage

  def upload_imagen(conn, %{"id" => id, "imagen" => imagen}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = DaleApp.Repo.get(DaleApp.Brands.Brand, product.brand_id)

    if brand.user_id == user_id do
      case Storage.upload_image(imagen.path, imagen.filename) do
        {:ok, %{body: body}} when is_map(body) ->
          image_url = body["secure_url"]
          Products.update_product(product, %{image: image_url, active: true})
          json(conn, %{ok: true, url: image_url})
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          image_url = decoded["secure_url"]
          Products.update_product(product, %{image: image_url, active: true})
          json(conn, %{ok: true, url: image_url})
        _ ->
          json(conn, %{ok: false, error: "Error al subir imagen"})
      end
    else
      json(conn, %{ok: false})
    end
  end

  def update_nombre(conn, %{"id" => id, "nombre" => nombre}) do
    user_id = get_session(conn, :user_id)
    product = Products.get_product(id)
    brand = DaleApp.Repo.get(DaleApp.Brands.Brand, product.brand_id)

    if brand.user_id == user_id do
      Products.update_product(product, %{name: nombre})
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end
end

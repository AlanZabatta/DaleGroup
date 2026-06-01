defmodule DaleAppWeb.BrandController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Accounts
  import Ecto.Query

  def mi_tienda(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    render(conn, :mi_tienda, brand: brand, cajeros: cajeros)
  end

  def update(conn, %{"brand" => brand_params}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    address = Map.get(brand_params, "address", "")
    direcciones = address |> String.split("|") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    # Geocodificar primera dirección para el pin principal
    brand_params = case direcciones do
      [primera | _] ->
        case geocode(primera) do
          {:ok, lat, lng} -> Map.merge(brand_params, %{"latitude" => lat, "longitude" => lng})
          _ -> brand_params
        end
      _ -> brand_params
    end

    brand
    |> Brand.changeset(brand_params)
    |> Repo.update()

    # Borrar locations anteriores y recrear
    Repo.delete_all(from l in DaleApp.Brands.BrandLocation, where: l.brand_id == ^brand.id)

    Enum.each(direcciones, fn dir ->
      case geocode(dir) do
        {:ok, lat, lng} ->
          %DaleApp.Brands.BrandLocation{}
          |> DaleApp.Brands.BrandLocation.changeset(%{
            brand_id: brand.id,
            address: dir,
            latitude: lat,
            longitude: lng
          })
          |> Repo.insert()
        _ -> :ok
      end
    end)

    conn
    |> put_flash(:info, "Tienda actualizada.")
    |> redirect(to: ~p"/mi-stand")
  end

  def cajeros(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    render(conn, :cajeros, brand: brand, cajeros: cajeros)
  end

  def remove_cajero(conn, %{"id" => id}) do
    user = Accounts.get_user(id)
    Accounts.remove_cajero(user)

    conn
    |> put_flash(:info, "Cajero eliminado.")
    |> redirect(to: ~p"/mi-tienda/cajeros")
  end

  def mi_stand(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    if brand do
      redirect(conn, to: ~p"/marcas/#{brand.id}")
    else
      redirect(conn, to: ~p"/")
    end
  end

  def unirse(conn, %{"brand_id" => brand_id}) do
    user_id = get_session(conn, :user_id)

    if is_nil(user_id) do
      conn
      |> put_session(:join_brand_id, brand_id)
      |> redirect(to: ~p"/auth/google")
    else
      user = Accounts.get_user(user_id)
      brand = Repo.get(Brand, brand_id)

      case Accounts.assign_cajero(user, String.to_integer(brand_id)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Ahora sos cajero de #{brand.name}.")
          |> redirect(to: ~p"/")
        {:error, _} ->
          conn
          |> put_flash(:error, "Error al unirse.")
          |> redirect(to: ~p"/")
      end
    end
  end

  defp geocode(address) do
    url = "https://nominatim.openstreetmap.org/search"
    case Req.get(url, params: [q: address, format: "json", limit: 1], headers: [{"User-Agent", "DaleGroup/1.0"}]) do
      {:ok, %{body: [%{"lat" => lat, "lon" => lng} | _]}} ->
        {:ok, String.to_float(lat), String.to_float(lng)}
      _ ->
        {:error, :not_found}
    end
  end


  def upload_logo(conn, %{"id" => id, "logo" => logo}) do
    user_id = get_session(conn, :user_id)
    brand = DaleApp.Repo.get(DaleApp.Brands.Brand, id)
    if brand.user_id == user_id do
      case DaleApp.Storage.upload_image(logo.path, logo.filename) do
        {:ok, %{body: body}} when is_map(body) ->
          url = body["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{logo: url}))
          json(conn, %{ok: true, url: url})
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          url = decoded["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{logo: url}))
          json(conn, %{ok: true, url: url})
        _ ->
          json(conn, %{ok: false, error: "Error al subir logo"})
      end
    else
      json(conn, %{ok: false})
    end
  end
end

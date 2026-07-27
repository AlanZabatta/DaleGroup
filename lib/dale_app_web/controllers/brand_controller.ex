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
    curva_cupon = if brand do
      hoy = Date.utc_today()
      hace_30_dias = DateTime.utc_now() |> DateTime.add(-30, :day)

      claims_por_dia =
        from(cl in DaleApp.Claims.Claim,
          where: cl.brand_id == ^brand.id and cl.inserted_at >= ^hace_30_dias,
          group_by: fragment("date(?)", cl.inserted_at),
          select: {fragment("date(?)", cl.inserted_at), count(cl.id)}
        )
        |> Repo.all()
        |> Map.new()

      for i <- 29..0//-1 do
        dia = Date.add(hoy, -i)
        Map.get(claims_por_dia, dia, 0)
      end
    else
      List.duplicate(0, 30)
    end

    render(conn, :mi_tienda, brand: brand, cajeros: cajeros, curva_cupon: curva_cupon, interes_cupon: Enum.sum(curva_cupon))
  end
  def actualizar_colores(conn, params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    colores = %{
      "principal" => Map.get(params, "principal", "#186904"),
      "fondo" => Map.get(params, "fondo", "#ffffff"),
      "letras" => Map.get(params, "letras", "#1a1a1a"),
      "gestion" => Map.get(params, "gestion", "#ffffff")
    }
    case brand |> Brand.changeset(%{colores: colores}) |> Repo.update() do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> json(conn, %{ok: false})
    end
  end


  def update(conn, %{"brand" => brand_params}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    # Convertir categorias de string CSV a lista
    brand_params = case Map.get(brand_params, "categorias") do
      nil -> Map.put(brand_params, "categorias", [])
      "" -> Map.put(brand_params, "categorias", [])
      cats when is_binary(cats) ->
        lista = cats |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(brand_params, "categorias", lista)
      _ -> brand_params
    end

    address = Map.get(brand_params, "address", "")
    direcciones = address |> String.split("|") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    brand_params = case direcciones do
      [primera | _] ->
        case geocode(primera) do
          {:ok, lat, lng} -> Map.merge(brand_params, %{"latitude" => lat, "longitude" => lng})
          _ -> brand_params
        end
      _ -> brand_params
    end

    nombre_val = (Map.get(brand_params, "name", brand.name) || "") |> String.trim()
    categorias_val = Map.get(brand_params, "categorias", brand.categorias || [])
    completo? = nombre_val != "" && direcciones != [] && categorias_val != []
    brand_params = Map.put(brand_params, "active", completo?)

    brand
    |> Brand.changeset(brand_params)
    |> Repo.update()

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

  def cajero_detalle(conn, %{"id" => id}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajero = Accounts.get_user(id)
    if brand && cajero && cajero.cajero_brand_id == brand.id do
      render(conn, :cajero_detalle, brand: brand, cajero: cajero)
    else
      conn
      |> put_flash(:error, "No encontrado.")
      |> redirect(to: ~p"/mi-tienda/cajeros")
    end
  end

  def actualizar_cajero(conn, %{"id" => id} = params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajero = Accounts.get_user(id)
    if brand && cajero && cajero.cajero_brand_id == brand.id do
      atributos = %{
        "telefono" => Map.get(params, "telefono", cajero.telefono),
        "sede" => Map.get(params, "sede", cajero.sede),
        "zona" => Map.get(params, "zona", cajero.zona),
        "horario_laboral" => Map.get(params, "horario_laboral", cajero.horario_laboral)
      }
      cajero
      |> DaleApp.Accounts.User.changeset(atributos)
      |> Repo.update()
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end

  def subir_foto_cajero(conn, %{"id" => id, "foto" => foto}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajero = Accounts.get_user(id)
    if brand && cajero && cajero.cajero_brand_id == brand.id do
      case DaleApp.Storage.upload_image(foto.path, foto.filename) do
        {:ok, %{body: body}} when is_map(body) ->
          url = body["secure_url"]
          cajero |> Ecto.Changeset.change(%{avatar: url}) |> Repo.update()
          json(conn, %{ok: true, url: url})
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          url = decoded["secure_url"]
          cajero |> Ecto.Changeset.change(%{avatar: url}) |> Repo.update()
          json(conn, %{ok: true, url: url})
        _ ->
          json(conn, %{ok: false, error: "Error al subir foto"})
      end
    else
      json(conn, %{ok: false})
    end
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
    user = if user_id, do: Accounts.get_user(user_id), else: nil

    if is_nil(user) do
      conn
      |> clear_session()
      |> put_session(:join_brand_id, brand_id)
      |> redirect(to: ~p"/auth/google")
    else
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

  def buscar_direccion(conn, %{"q" => q}) do
    url = "https://nominatim.openstreetmap.org/search"
    case Req.get(url, params: [q: q, format: "json", limit: 5, addressdetails: 1, "accept-language": "es"], headers: [{"User-Agent", "DaleGroup/1.0"}]) do
      {:ok, %{body: resultados}} when is_list(resultados) and resultados != [] ->
        sugerencias = Enum.map(resultados, fn r ->
          %{display_name: r["display_name"], lat: r["lat"], lon: r["lon"], corto: armar_direccion_corta(r["address"] || %{})}
        end)
        json(conn, %{ok: true, sugerencias: sugerencias})
      _ ->
        json(conn, %{ok: false, sugerencias: []})
    end
  end

  defp armar_direccion_corta(address) do
    calle = address["road"] || ""
    numero = address["house_number"] || ""
    calle_numero = String.trim("#{calle} #{numero}")

    estado = address["state"] || ""
    es_caba = String.contains?(estado, "Ciudad Autónoma de Buenos Aires") || String.contains?(estado, "Capital Federal")

    if estado != "" && !es_caba do
      "#{calle_numero}, #{estado}"
    else
      calle_numero
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

  defp build_crop_params(params) do
    x = Map.get(params, "crop_x")
    y = Map.get(params, "crop_y")
    w = Map.get(params, "crop_w")
    h = Map.get(params, "crop_h")
    if x && y && w && h do
      [{"x", x}, {"y", y}, {"width", w}, {"height", h}, {"crop", "crop"}]
    else
      []
    end
  end

  def upload_logo(conn, %{"id" => id, "logo" => logo} = params) do
    user_id = get_session(conn, :user_id)
    brand = DaleApp.Repo.get(DaleApp.Brands.Brand, id)
    if brand.user_id == user_id do
      crop_params = build_crop_params(params)
      colores_actuales = brand.colores || %{}
      nuevos_colores = case Map.get(params, "logo_bg") do
        nil -> colores_actuales
        "" -> colores_actuales
        bg -> Map.put(colores_actuales, "logo_fondo", bg)
      end
      case DaleApp.Storage.upload_image(logo.path, logo.filename, crop_params) do
        {:ok, %{body: body}} when is_map(body) ->
          url = body["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{logo: url, colores: nuevos_colores}))
          json(conn, %{ok: true, url: url})
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          url = decoded["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{logo: url, colores: nuevos_colores}))
          json(conn, %{ok: true, url: url})
        _ ->
          json(conn, %{ok: false, error: "Error al subir logo"})
      end
    else
      json(conn, %{ok: false})
    end
  end

  def upload_cover(conn, %{"id" => id, "cover" => cover} = params) do
    user_id = get_session(conn, :user_id)
    brand = DaleApp.Repo.get(DaleApp.Brands.Brand, id)
    if brand.user_id == user_id do
      crop_params = build_crop_params(params)
      resultado_cover = DaleApp.Storage.upload_image(cover.path, cover.filename, crop_params)
      IO.inspect(resultado_cover, label: "RESULTADO CLOUDINARY COVER")
      case resultado_cover do
        {:ok, %{body: body}} when is_map(body) ->
          url = body["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{cover_image: url}))
          json(conn, %{ok: true, url: url})
        {:ok, %{body: body}} when is_binary(body) ->
          decoded = Jason.decode!(body)
          url = decoded["secure_url"]
          DaleApp.Repo.update!(Ecto.Changeset.change(brand, %{cover_image: url}))
          json(conn, %{ok: true, url: url})
        _ ->
          json(conn, %{ok: false, error: "Error al subir cover"})
      end
    else
      json(conn, %{ok: false})
    end
  end
end

defmodule DaleAppWeb.PageController do
  use DaleAppWeb, :controller
  import Ecto.Query
  alias DaleApp.Accounts
  alias DaleApp.Brands.Brand
  alias DaleApp.Coupons.Coupon
  alias DaleApp.Repo

  def home(conn, _params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    featured_brands = Repo.all(
      from b in Brand,
      where: not is_nil(b.featured_slot) and b.active == true,
      order_by: b.featured_slot
    )
    featured_brands = Enum.map(featured_brands, fn brand ->
      cupon = Repo.one(
        from c in Coupon,
        where: c.brand_id == ^brand.id and c.active == true and c.stock > 0,
        order_by: [desc: c.inserted_at],
        limit: 1
      )
      Map.put(brand, :cupon_activo, cupon)
    end)
    render(conn, :home, current_user: current_user, featured_brands: featured_brands)
  end

  def perfil(conn, _params) do
    user_id = get_session(conn, :user_id)
    if is_nil(user_id) do
      redirect(conn, to: "/auth/google")
    else
      current_user = Accounts.get_user(user_id)
      amigos = DaleApp.Friends.friends_list(user_id)
      favoritos = DaleApp.Favorites.list_user_favorites(user_id)
      render(conn, :perfil, current_user: current_user, amigos: amigos, favoritos: favoritos)
    end
  end

  def amigos(conn, _params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    solicitudes = if user_id, do: DaleApp.Friends.pending_requests(user_id), else: []
    amigos = if user_id, do: DaleApp.Friends.friends_list(user_id), else: []
    amigo_ids = Enum.map(amigos, & &1.id)
    publicaciones = if user_id, do: DaleApp.Publicaciones.listar_de_amigos(user_id, amigo_ids), else: []
    pub_ids = Enum.map(publicaciones, & &1.id)
    {likes_conteo, mis_likes} = if user_id, do: DaleApp.Likes.likes_por_publicaciones(pub_ids, user_id), else: {%{}, MapSet.new()}
    render(conn, :amigos, current_user: current_user, solicitudes: solicitudes, amigos: amigos, publicaciones: publicaciones, likes_conteo: likes_conteo, mis_likes: mis_likes)
  end

  def productos(conn, params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    orden = Map.get(params, "orden")
    query = from p in DaleApp.Products.Product,
      join: b in DaleApp.Brands.Brand, on: p.brand_id == b.id,
      where: p.active == true and not is_nil(p.image) and b.active == true,
      select: %{producto: p, marca: b}
    productos = Repo.all(query)
    productos = case orden do
      "mayor_menor" ->
        Enum.sort_by(productos, fn %{producto: p, marca: b} ->
          -(Integer.parse(to_string(b.discount || 0)) |> elem(0))
        end)
      "menor_mayor" ->
        Enum.sort_by(productos, fn %{producto: p} -> p.price || 0 end)
      _ ->
        productos
    end
    render(conn, :productos, current_user: current_user, productos: productos, orden: orden)
  end

  def tiendas(conn, params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    orden = Map.get(params, "orden")

    todas_las_marcas = Repo.all(
      from b in Brand,
      where: b.active == true,
      order_by: b.name
    )
    todas_las_marcas = Enum.map(todas_las_marcas, fn brand ->
      cupon = Repo.one(
        from c in Coupon,
        where: c.brand_id == ^brand.id and c.active == true and c.stock > 0,
        order_by: [desc: c.inserted_at],
        limit: 1
      )
      Map.put(brand, :cupon_activo, cupon)
    end)

    todas_las_marcas = if orden == "mayor_menor" do
      Enum.sort_by(todas_las_marcas, fn b ->
        case b.cupon_activo do
          nil -> -1
          c ->
            case Integer.parse(to_string(c.discount)) do
              {n, _} -> n
              :error -> -1
            end
        end
      end, :desc)
    else
      todas_las_marcas
    end

    render(conn, :tiendas, current_user: current_user, todas_las_marcas: todas_las_marcas, orden: orden)
  end

  def mapa(conn, _params) do
    user_id = get_session(conn, :user_id)
    marcas = DaleApp.Repo.all(
      from b in DaleApp.Brands.Brand,
      where: b.active == true and not is_nil(b.latitude)
    )
    marcas = Enum.map(marcas, fn brand ->
      cupon = DaleApp.Repo.one(
        from c in DaleApp.Coupons.Coupon,
        where: c.brand_id == ^brand.id and c.active == true and c.stock > 0,
        order_by: [desc: c.inserted_at],
        limit: 1
      )
      Map.put(brand, :cupon_activo, cupon)
    end)
    locations = DaleApp.Repo.all(DaleApp.Brands.BrandLocation)
    saved_brand_ids = if user_id do
      DaleApp.MapSaves.list_user_map(user_id) |> Enum.map(& &1.brand_id)
    else
      []
    end
    render(conn, :mapa, marcas: marcas, locations: locations, saved_brand_ids: saved_brand_ids)
  end
  @palabras_prohibidas ~w(
    fuck shit ass bitch nigger faggot cunt whore slut pussy dick cock bastard asshole motherfucker
    puta mierda concha pija culo boludo pelotudo forro cagon cago choto puto garca hdp ctm
    hitler nazi fascist kkk antisemite jew_killer judiomaldito muertejudio
    rape murder kill terrorist isis bomb
    admin root superuser moderator official dalegroup dale_group
  )

  def cambiar_username(conn, %{"username" => username}) do
    user_id = get_session(conn, :user_id)
    username = String.trim(username)

    cond do
      String.length(username) < 4 ->
        json(conn, %{ok: false, error: "Mínimo 4 caracteres"})

      String.length(username) > 20 ->
        json(conn, %{ok: false, error: "Máximo 20 caracteres"})

      not Regex.match?(~r/^[a-zA-Z0-9_]+$/, username) ->
        json(conn, %{ok: false, error: "Solo letras, números y guión bajo"})

      Enum.any?(@palabras_prohibidas, fn p -> String.contains?(String.downcase(username), p) end) ->
        json(conn, %{ok: false, error: "Ese nombre no está permitido"})

      true ->
        user = Accounts.get_user(user_id)
        es_admin_o_dueno = user.role in ["admin", "dueño"]
        puede_cambiar = if es_admin_o_dueno do
          true
        else
          case user.username_changed_at do
            nil -> true
            last ->
              diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), last, :second)
              diff >= 7 * 24 * 3600
          end
        end

        cond do
          not puede_cambiar ->
            last = user.username_changed_at
            diff_days = div(7 * 24 * 3600 - NaiveDateTime.diff(NaiveDateTime.utc_now(), last, :second), 86400)
            json(conn, %{ok: false, error: "Podés cambiar tu nombre en #{diff_days + 1} días"})

          DaleApp.Repo.get_by(DaleApp.Accounts.User, username: username) != nil ->
            json(conn, %{ok: false, error: "Ese nombre ya está en uso"})

          true ->
            user |> DaleApp.Accounts.User.changeset(%{username: username, username_changed_at: NaiveDateTime.utc_now()}) |> DaleApp.Repo.update()
            json(conn, %{ok: true, username: username})
        end
    end
  end

  def cambiar_foto(conn, %{"foto" => foto}) do
    user_id = get_session(conn, :user_id)
    user = Accounts.get_user(user_id)

    # Borrar foto anterior de Cloudinary si no es de Google
    if user.avatar && !String.contains?(user.avatar, "googleusercontent") do
      public_id = user.avatar
        |> String.split("/")
        |> List.last()
        |> String.split(".")
        |> List.first()
      DaleApp.Storage.delete_image(public_id)
    end

    case DaleApp.Storage.upload_image(foto.path, foto.filename) do
      {:ok, %{body: %{"secure_url" => url}}} ->
        user |> DaleApp.Accounts.User.changeset(%{avatar: url}) |> DaleApp.Repo.update()
        json(conn, %{ok: true, url: url})
      _ ->
        json(conn, %{ok: false, error: "Error al subir foto"})
    end
  end

end

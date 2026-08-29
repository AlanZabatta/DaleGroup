
defmodule DaleAppWeb.MiTiendaLive do
  use DaleAppWeb, :live_view
 
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Brands.Brand
  alias DaleApp.Brands.BrandLocation
 
  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    ubicaciones = if brand, do: Repo.all(from(l in BrandLocation, where: l.brand_id == ^brand.id)), else: []

    # Sede por default para el empleado del mes: primera sede si la marca
    # tiene, o nil (toda la marca) si no tiene ninguna cargada.
    sede_actual = List.first(ubicaciones)
    empleados_del_mes = if brand, do: ganadores_ciclo_actual(brand, sede_actual && sede_actual.id), else: []

    {total_productos, productos_dale, limite_dale, hay_sin_stock_normal, hay_sin_stock_dale} =
      if brand do
        productos_brand = DaleApp.Products.list_brand_products(brand.id)
        productos_activos = Enum.filter(productos_brand, & &1.active)

        total = productos_activos |> Enum.map(& &1.name) |> Enum.uniq() |> length()

        dale =
          productos_activos
          |> Enum.filter(&(&1.codigo_tipo == "99"))
          |> Enum.map(& &1.name)
          |> Enum.uniq()
          |> length()

        limite = brand.image_limit || 12

        tipos_sin_stock =
          from(s in DaleApp.Products.StockItem,
            join: p in DaleApp.Products.Product, on: p.id == s.product_id,
            where: p.brand_id == ^brand.id,
            group_by: [p.id, p.codigo_tipo],
            having: sum(s.cantidad) <= 0,
            select: p.codigo_tipo
          )
          |> Repo.all()

        sin_stock_normal = Enum.any?(tipos_sin_stock, &(&1 != "99"))
        sin_stock_dale = Enum.any?(tipos_sin_stock, &(&1 == "99"))

        {total, dale, limite, sin_stock_normal, sin_stock_dale}
      else
        {0, 0, 12, false, false}
      end
 
    curva_cupon =
      if brand do
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
 
    {:ok,
     assign(socket,
       brand: brand,
       cajeros: cajeros,
       ubicaciones: ubicaciones,
       curva_cupon: curva_cupon,
       interes_cupon: Enum.sum(curva_cupon),
       total_productos: total_productos,
       productos_dale: productos_dale,
       limite_dale: limite_dale,
       hay_sin_stock_normal: hay_sin_stock_normal,
       hay_sin_stock_dale: hay_sin_stock_dale,
       empleados_del_mes: empleados_del_mes,
       sede_actual: sede_actual,
       mostrar_selector_sede: false
     )}
  end

  # El "empleado del mes" es el ganador (o los ganadores, si hay empate sin
  # desempatar) del ciclo de 30 dias mas reciente que ya cerro. Si el
  # sistema de puntos no esta activo, o todavia no cerro ningun ciclo, no
  # hay nada que mostrar.
  defp nombre_corto(usuario) do
    cond do
      usuario.apellido_visible && usuario.apellido_visible != "" ->
        usuario.apellido_visible

      true ->
        (usuario.name || "?") |> String.split(" ", parts: 2) |> List.first() || "?"
    end
  end

  def handle_event("toggle_selector_sede", _params, socket) do
    {:noreply, assign(socket, mostrar_selector_sede: !socket.assigns.mostrar_selector_sede)}
  end

  def handle_event("elegir_sede", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    sede = Enum.find(socket.assigns.ubicaciones, fn s -> s.id == id end)
    empleados_del_mes = ganadores_ciclo_actual(socket.assigns.brand, sede && sede.id)

    {:noreply,
     assign(socket,
       sede_actual: sede,
       mostrar_selector_sede: false,
       empleados_del_mes: empleados_del_mes
     )}
  end

  def handle_event("elegir_todas_sedes", _params, socket) do
    empleados_del_mes = ganadores_ciclo_actual(socket.assigns.brand, nil)

    {:noreply,
     assign(socket,
       sede_actual: nil,
       mostrar_selector_sede: false,
       empleados_del_mes: empleados_del_mes
     )}
  end

  defp texto_sede_actual(sedes, sede_actual) do
    cond do
      Enum.empty?(sedes) -> "Elegir sede"
      sede_actual -> sede_actual.nombre
      true -> "Todas"
    end
  end

  defp ganadores_ciclo_actual(brand, sede_id) do
    case brand.empleado_puntos_activada_en do
      nil ->
        []

      activada_en ->
        ciclo_cerrado =
          activada_en
          |> DaleApp.Products.Puntos.ciclos_desde()
          |> DaleApp.Products.Puntos.ciclos_cerrados()
          |> List.last()

        case ciclo_cerrado do
          nil ->
            []

          {inicio, fin} ->
            DaleApp.Products.EmpleadoDelMes.calcular_ciclo(brand, inicio, fin, sede_id)
            |> Enum.filter(& &1.es_ganador)
        end
    end
  end

  def handle_event("volver_mi_stand", _params, socket) do
    brand = socket.assigns.brand
    {:noreply, push_navigate(socket, to: ~p"/marcas/#{brand.id}")}
  end

  def handle_event("guardar_gestion", %{"brand" => brand_params}, socket) do
    brand = socket.assigns.brand
 
    brand_params =
      case Map.get(brand_params, "categorias") do
        nil ->
          Map.put(brand_params, "categorias", [])
 
        "" ->
          Map.put(brand_params, "categorias", [])
 
        cats when is_binary(cats) ->
          lista = cats |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
          Map.put(brand_params, "categorias", lista)
 
        _ ->
          brand_params
      end
 
    address = Map.get(brand_params, "address", "")
    direcciones = address |> String.split("|") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
 
    brand_params =
      case direcciones do
        [primera | _] ->
          case geocode(primera) do
            {:ok, lat, lng} -> Map.merge(brand_params, %{"latitude" => lat, "longitude" => lng})
            _ -> brand_params
          end
 
        _ ->
          brand_params
      end
 
    nombre_val = (Map.get(brand_params, "name", brand.name) || "") |> String.trim()
    categorias_val = Map.get(brand_params, "categorias", brand.categorias || [])
    completo? = nombre_val != "" && direcciones != [] && categorias_val != []
    brand_params = Map.put(brand_params, "active", completo?)
 
    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(brand_params)
      |> Repo.update()
 
    completas_actuales =
      (Map.get(brand_params, "address_full") || brand.address_full || "")
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
 
    Repo.delete_all(from(l in BrandLocation, where: l.brand_id == ^brand.id))
 
    direcciones
    |> Enum.with_index()
    |> Enum.each(fn {dir, i} ->
      case geocode(dir) do
        {:ok, lat, lng} ->
          %BrandLocation{}
          |> BrandLocation.changeset(%{
            brand_id: brand.id,
            address: dir,
            direccion_completa: Enum.at(completas_actuales, i),
            latitude: lat,
            longitude: lng
          })
          |> Repo.insert()
 
        _ ->
          :ok
      end
    end)
 
    {:noreply,
     socket
     |> assign(brand: brand_actualizada)
     |> push_navigate(to: ~p"/mi-stand")}
  end
 
  def handle_event("imagen_actualizada", _params, socket) do
    brand = Repo.get!(Brand, socket.assigns.brand.id)
    {:noreply, assign(socket, brand: brand)}
  end
 
  def handle_event("pin_generado", _params, socket) do
    brand = Repo.get!(Brand, socket.assigns.brand.id)
    {:noreply, assign(socket, brand: brand)}
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
 
  def render(assigns) do
    ~H"""
    <div id="aviso-error-gestion" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
      <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px 22px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
        <div style="width:64px; height:64px; margin:0 auto 14px; border:4px solid #c0392b; border-radius:50%; display:flex; align-items:center; justify-content:center;">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#c0392b" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#c0392b"/></svg>
        </div>
        <p style="font-size:20px; font-weight:700; color:#c0392b; margin:0 0 12px; font-family:Poppins,sans-serif;">Dirección inválida</p>
        <div style="height:2px; width:60px; background:#c0392b; border-radius:2px; margin:0 auto 14px;"></div>
        <p id="aviso-error-gestion-texto" style="font-size:14px; color:#555; margin:0 0 22px; line-height:1.5; font-family:Poppins,sans-serif;">Elegí una dirección de la lista de sugerencias, no la escribas libremente.</p>
        <button onclick="document.getElementById('aviso-error-gestion').style.display='none'" style="width:100%; background:#186904; color:#fff; border:none; border-radius:14px; padding:13px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Entendido</button>
      </div>
    </div>
 
    <div id="aviso-confirmar-vacios" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
      <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px 22px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
        <div style="width:64px; height:64px; margin:0 auto 14px; border:4px solid #186904; border-radius:50%; display:flex; align-items:center; justify-content:center;">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#186904" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#186904"/></svg>
        </div>
        <p style="font-size:20px; font-weight:700; color:#186904; margin:0 0 12px; font-family:Poppins,sans-serif;">Antes de continuar</p>
        <div style="height:2px; width:60px; background:#186904; border-radius:2px; margin:0 auto 14px;"></div>
        <p id="aviso-confirmar-vacios-texto" style="font-size:14px; color:#555; margin:0 0 22px; line-height:1.5; font-family:Poppins,sans-serif; text-align:left;"></p>
        <div style="display:flex; gap:10px;">
          <button onclick="continuarGuardadoGestion()" style="flex:1; background:#186904; color:#fff; border:none; border-radius:14px; padding:13px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Sí</button>
          <button onclick="document.getElementById('aviso-confirmar-vacios').style.display='none'" style="flex:1; background:#fff; color:#186904; border:2px solid #186904; border-radius:14px; padding:11px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">No</button>
        </div>
      </div>
    </div>
 
    <div id="aviso-salir-sin-guardar" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
      <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px 22px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
        <div style="width:64px; height:64px; margin:0 auto 14px; border:4px solid #186904; border-radius:50%; display:flex; align-items:center; justify-content:center;">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#186904" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#186904"/></svg>
        </div>
        <p style="font-size:20px; font-weight:700; color:#186904; margin:0 0 12px; font-family:Poppins,sans-serif;">Cambios sin guardar</p>
        <div style="height:2px; width:60px; background:#186904; border-radius:2px; margin:0 auto 14px;"></div>
        <p id="aviso-salir-texto" style="font-size:14px; color:#555; margin:0 0 22px; line-height:1.5; font-family:Poppins,sans-serif;"></p>
        <div style="display:flex; gap:10px;">
          <button onclick="guardarYSalir()" style="flex:1; background:#186904; color:#fff; border:none; border-radius:14px; padding:13px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Guardar</button>
          <button onclick="salirSinGuardar()" style="flex:1; background:#fff; color:#186904; border:2px solid #186904; border-radius:14px; padding:11px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">No guardar</button>
        </div>
      </div>
    </div>
 
    <div id="mi-tienda-root" phx-hook=".MiTiendaHook" style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="#" onclick="intentarVolver(event)" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mi Tienda</p>
        <div style="position: relative; display: flex; align-items: center; justify-content: space-between; gap: 10px; background: linear-gradient(160deg, #ffffff 0%%, #f6faf3 100%%); border: 1.5px solid #d9ead9; border-radius: 14px; padding: 10px 14px; margin-bottom: 16px; box-shadow: 0 3px 10px rgba(24,105,4,0.08);">
          <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif;">
            Sede: <span style="font-weight: 800;"><%= texto_sede_actual(@ubicaciones, @sede_actual) %></span>
          </p>
          <button type="button" phx-click="toggle_selector_sede" style="display: flex; align-items: center; gap: 6px; background: white; border: 1.5px solid #186904; border-radius: 20px; padding: 6px 12px; cursor: pointer; font-family: Poppins, sans-serif; font-size: 12px; font-weight: 700; color: #186904;">
            <%= texto_sede_actual(@ubicaciones, @sede_actual) %>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style={"transition: transform 0.15s; transform: rotate(#{if @mostrar_selector_sede, do: "180deg", else: "0deg"});"}>
              <polyline points="6 9 12 15 18 9"/>
            </svg>
          </button>
          <%= if @mostrar_selector_sede do %>
            <div style="position: absolute; top: calc(100% + 6px); right: 0; z-index: 20; background: white; border: 1.5px solid #eee; border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,0.12); min-width: 180px; overflow: hidden;">
              <%= if Enum.empty?(@ubicaciones) do %>
                <p style="font-size: 12.5px; color: #999; margin: 0; padding: 14px; font-family: Poppins, sans-serif; text-align: center;">Todavía no cargás sedes.</p>
              <% else %>
                <%= if length(@ubicaciones) > 1 do %>
                  <button type="button" phx-click="elegir_todas_sedes" style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; border-bottom: 1px solid #f2f2f2; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; background: #{if is_nil(@sede_actual), do: "#eef4ec", else: "white"}; color: #{if is_nil(@sede_actual), do: "#186904", else: "#333"};"}>
                    Todas las sedes
                  </button>
                <% end %>
                <%= for sede <- @ubicaciones do %>
                  <button type="button" phx-click="elegir_sede" phx-value-id={sede.id} style={"display: block; width: 100%; text-align: left; padding: 12px 16px; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 600; background: #{if @sede_actual && @sede_actual.id == sede.id, do: "#eef4ec", else: "white"}; color: #{if @sede_actual && @sede_actual.id == sede.id, do: "#186904", else: "#333"};"}>
                    <%= sede.nombre %>
                  </button>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <%= if @brand do %>
        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Stock</p>
        <.link navigate="/mi-tienda/stock" style="display: block; text-decoration: none; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 20px; padding: 18px 20px; margin-bottom: 12px; box-shadow: 0 4px 14px rgba(24,105,4,0.10);">
          <p style="font-size: 11px; font-weight: 800; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1.2px;">MiniParonama</p>
          <div style="display: flex; align-items: flex-end; gap: 14px;">
            <div style="position: relative; padding: 10px 16px; border-radius: 14px; background: #e6f2e3; border: 1.5px solid #186904;">
              <%= if @hay_sin_stock_normal do %>
                <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
              <% end %>
              <p style="font-size: 28px; font-weight: 800; color: #186904; margin: 0; line-height: 1; letter-spacing: -0.5px;"><%= @total_productos %></p>
              <p style="font-size: 11px; color: #7a9a76; margin: 5px 0 0; font-weight: 600;">productos totales</p>
            </div>
            <div style="position: relative; padding: 10px 16px; border-radius: 14px; background: #e6f2e3; border: 1.5px solid #186904;">
              <%= if @hay_sin_stock_dale do %>
                <span style="position: absolute; top: -3px; right: -3px; width: 10px; height: 10px; border-radius: 50%; background: #c0392b; box-shadow: 0 0 0 2px white;"></span>
              <% end %>
              <p style="font-size: 28px; font-weight: 800; color: #186904; margin: 0; line-height: 1; letter-spacing: -0.5px;"><%= @productos_dale %><span style="font-size: 16px; color: #aaa; font-weight: 700;">/<%= @limite_dale %></span></p>
              <p style="font-size: 11px; color: #7a9a76; margin: 5px 0 0; font-weight: 600;">productos Dale</p>
            </div>
          </div>
          <%= if @hay_sin_stock_normal || @hay_sin_stock_dale do %>
            <div style="margin-top: 12px; display: flex; flex-direction: column; gap: 4px;">
              <%= if @hay_sin_stock_normal do %>
                <div style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 6px; height: 6px; border-radius: 50%; background: #c0392b; flex-shrink: 0;"></span>
                  <p style="font-size: 12px; color: #c0392b; margin: 0; font-weight: 600; font-family: Poppins, sans-serif;">Tenés productos sin unidades en tu stock</p>
                </div>
              <% end %>
              <%= if @hay_sin_stock_dale do %>
                <div style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 6px; height: 6px; border-radius: 50%; background: #c0392b; flex-shrink: 0;"></span>
                  <p style="font-size: 12px; color: #c0392b; margin: 0; font-weight: 600; font-family: Poppins, sans-serif;">Tenés productos sin unidades en Dale</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </.link>
        <.link navigate="/mi-tienda/stock" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar Stock
        </.link>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>
 
        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Mis Productos</p>
 
        <style>
          @keyframes blurCambioPrecio {
            0% { filter: blur(0px); opacity: 1; }
            45% { filter: blur(6px); opacity: 0.3; }
            55% { filter: blur(6px); opacity: 0.3; }
            100% { filter: blur(0px); opacity: 1; }
          }
          .precio-animado { animation: blurCambioPrecio 0.6s ease; }
        </style>
 
        <a href="/mi-tienda/productos" style="text-decoration: none; display: block; margin-bottom: 16px;">
          <div style="display: flex; gap: 10px;">
            <div style="flex: 1; display: flex; flex-direction: column; border-radius: 16px; overflow: hidden; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: white;">
              <div style="aspect-ratio: 3/4; background: white; display: flex; align-items: center; justify-content: center;">
                <svg width="60%" height="60%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>
                </svg>
              </div>
              <div style="background: white; padding: 8px 10px;">
                <p style="font-size: 12px; color: #888; margin: 0;">Remera</p>
                <p id="precio-demo-1" class="precio-animado" style="font-size: 15px; font-weight: 700; color: #186904; margin: 0;">$99000</p>
              </div>
            </div>
            <div style="flex: 1; display: flex; flex-direction: column; border-radius: 16px; overflow: hidden; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: white;">
              <div style="aspect-ratio: 3/4; background: white; display: flex; align-items: center; justify-content: center;">
                <svg width="65%" height="65%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M4 6h5.426a1 1 0 0 1 .863 .496l1.064 1.823a3 3 0 0 0 1.896 1.407l4.677 1.114a4 4 0 0 1 3.074 3.89v2.27a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1v-10a1 1 0 0 1 1 -1"/>
                  <path d="M14 13l1 -2"/>
                  <path d="M8 18v-1a4 4 0 0 0 -4 -4h-1"/>
                  <path d="M10 12l1.5 -3"/>
                </svg>
              </div>
              <div style="background: white; padding: 8px 10px;">
                <p style="font-size: 12px; color: #888; margin: 0;">Zapatilla</p>
                <p id="precio-demo-2" class="precio-animado" style="font-size: 15px; font-weight: 700; color: #186904; margin: 0;">$40000</p>
              </div>
            </div>
          </div>
        </a>
 
        <script>
          (function() {
            const precios1 = [99000, 40000, 76000, 58000];
            const precios2 = [40000, 76000, 99000, 58000];
            let idx = 0;
            setInterval(() => {
              idx = (idx + 1) % precios1.length;
              const el1 = document.getElementById('precio-demo-1');
              const el2 = document.getElementById('precio-demo-2');
              if (el1 && el2) {
                el1.classList.remove('precio-animado'); void el1.offsetWidth; el1.classList.add('precio-animado');
                el2.classList.remove('precio-animado'); void el2.offsetWidth; el2.classList.add('precio-animado');
                setTimeout(() => {
                  el1.textContent = '$' + precios1[idx].toLocaleString('es-AR');
                  el2.textContent = '$' + precios2[idx].toLocaleString('es-AR');
                }, 270);
              }
            }, 2600);
          })();
        </script>
 
        <a href="/mi-tienda/productos" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar ProductosDale
        </a>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>
 
        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Mis Empleados</p>
        <.link navigate="/mi-tienda/cajeros" style="text-decoration: none; background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 20px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08); display: flex; flex-direction: column; align-items: center; margin-bottom: 12px;">
          <%= if @empleados_del_mes == [] do %>
            <div style="position: relative; margin-bottom: 4px;">
              <svg width="26" height="26" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -18px; left: 50%; transform: translateX(-50%); filter: drop-shadow(0 2px 3px rgba(0,0,0,0.2));"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
              <div style="width: 60px; height: 60px; border-radius: 50%; background: white; border: 2px solid #f0f0f0; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.08);">
                <span style="font-size: 26px; color: #111; font-weight: 800;">?</span>
              </div>
            </div>
          <% else %>
            <div style="display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; margin-bottom: 4px;">
              <%= for logro <- @empleados_del_mes do %>
                <% ganador = logro.user %>
                <div style="display: flex; flex-direction: column; align-items: center; width: 56px;">
                  <div style="position: relative; margin-bottom: 4px;">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -14px; left: 50%; transform: translateX(-50%); filter: drop-shadow(0 2px 3px rgba(0,0,0,0.2));"><path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/></svg>
                    <div style="width: 52px; height: 52px; border-radius: 50%; background: white; border: 2px solid #f0f0f0; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.08); overflow: hidden;">
                      <%= if ganador && ganador.avatar do %>
                        <img src={ganador.avatar} style="width: 100%; height: 100%; object-fit: cover;" />
                      <% else %>
                        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                          <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                          <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                        </svg>
                      <% end %>
                    </div>
                  </div>
                  <p style="font-size: 10px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif; max-width: 56px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                    <%= ganador && nombre_corto(ganador) %>
                  </p>
                </div>
              <% end %>
            </div>
          <% end %>
          <p style="font-size: 11px; color: #999; margin: 6px 0 0; font-family: Poppins, sans-serif; text-align: center;">
            <%= cond do %>
              <% @empleados_del_mes == [] -> %>Todavía no hay empleado del mes
              <% length(@empleados_del_mes) > 1 -> %>Empleados del mes (empate)
              <% true -> %>Empleado del mes
            <% end %>
          </p>
        </.link>
        <.link navigate="/mi-tienda/cajeros" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar empleados (<%= length(@cajeros) %>)
        </.link>
 
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>

        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Mi Cupón</p>
 
    <%
      max_valor = Enum.max([1 | @curva_cupon])
      ancho_svg = 300
      alto_svg = 100
      cantidad = length(@curva_cupon)
 
      lista_puntos =
        @curva_cupon
        |> Enum.with_index()
        |> Enum.map(fn {valor, i} ->
          x = i / (cantidad - 1) * ancho_svg
          y = alto_svg - (valor / max_valor * (alto_svg - 20)) - 10
          {Float.round(x, 2), Float.round(y, 2)}
        end)
 
      arr_puntos = List.to_tuple(lista_puntos)
      n_puntos = tuple_size(arr_puntos)
 
      obtener_punto = fn i ->
        idx = max(0, min(n_puntos - 1, i))
        elem(arr_puntos, idx)
      end
 
      {x0, y0} = elem(arr_puntos, 0)
      path_suave =
        0..(n_puntos - 2)
        |> Enum.reduce("M #{x0},#{y0}", fn i, acc ->
          {x0i, y0i} = obtener_punto.(i - 1)
          {x1i, y1i} = obtener_punto.(i)
          {x2i, y2i} = obtener_punto.(i + 1)
          {x3i, y3i} = obtener_punto.(i + 2)
 
          c1x = Float.round(x1i + (x2i - x0i) / 6, 2)
          c1y = Float.round(y1i + (y2i - y0i) / 6, 2)
          c2x = Float.round(x2i - (x3i - x1i) / 6, 2)
          c2y = Float.round(y2i - (y3i - y1i) / 6, 2)
 
          acc <> " C #{c1x},#{c1y} #{c2x},#{c2y} #{x2i},#{y2i}"
        end)
 
      {_xf, _yf} = List.last(lista_puntos)
      path_area = path_suave <> " L #{ancho_svg},#{alto_svg} L 0,#{alto_svg} Z"
    %>
    <%
      hoy_fecha = Date.utc_today()
      meses_abrev = ~w(ene feb mar abr may jun jul ago sep oct nov dic)
      formatear_dia = fn dias_atras ->
        d = Date.add(hoy_fecha, -dias_atras)
        "#{d.day} #{Enum.at(meses_abrev, d.month - 1)}"
      end
 
      puntos_con_valor =
        lista_puntos
        |> Enum.zip(@curva_cupon)
        |> Enum.filter(fn {_, valor} -> valor > 0 end)
        |> Enum.map(fn {{x, y}, valor} -> {x, y, valor} end)
    %>
        <div style="background: white; border-radius: 18px; padding: 16px 18px; margin-bottom: 16px; border: 1.5px solid #186904; box-shadow: 0 3px 14px rgba(24,105,4,0.08);">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
            <p style="font-size: 11px; font-weight: 600; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1px; font-family: 'Noto Sans', sans-serif;">Canjes · últimos 30 días</p>
            <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0; font-family: 'Noto Sans', sans-serif;"><%= @interes_cupon %></p>
          </div>
          <svg width="100%" height="110" viewBox={"0 0 #{ancho_svg} #{alto_svg}"} preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="gradienteCupon" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#186904" stop-opacity="0.35"/>
                <stop offset="100%" stop-color="#186904" stop-opacity="0"/>
              </linearGradient>
              <filter id="brilloCupon" x="-20%" y="-20%" width="140%" height="140%">
                <feDropShadow dx="0" dy="0" stdDeviation="1.8" flood-color="#186904" flood-opacity="0.35"/>
              </filter>
            </defs>
            <line x1="0" y1={alto_svg * 0.33} x2={ancho_svg} y2={alto_svg * 0.33} stroke="#f2f2f2" stroke-width="1"/>
            <line x1="0" y1={alto_svg * 0.66} x2={ancho_svg} y2={alto_svg * 0.66} stroke="#f2f2f2" stroke-width="1"/>
            <path d={path_area} fill="url(#gradienteCupon)"/>
            <path d={path_suave} fill="none" stroke="#186904" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" filter="url(#brilloCupon)"/>
            <%= for {x, y, valor} <- puntos_con_valor do %>
              <circle cx={x} cy={y} r="3.5" fill="white" stroke="#186904" stroke-width="2"/>
              <title><%= valor %> canje<%= if valor != 1, do: "s" %></title>
            <% end %>
          </svg>
          <div style="display: flex; justify-content: space-between; margin-top: 6px;">
            <p style="font-size: 10px; color: #999; margin: 0; font-family: 'Noto Sans', sans-serif;"><%= formatear_dia.(29) %></p>
            <p style="font-size: 10px; color: #999; margin: 0; font-family: 'Noto Sans', sans-serif;"><%= formatear_dia.(15) %></p>
            <p style="font-size: 10px; color: #999; margin: 0; font-family: 'Noto Sans', sans-serif;">Hoy</p>
          </div>
        </div>
 
        <a href="/mi-tienda/cupon" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar cupón
        </a>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>
        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Mis Sedes</p>
        <%= if @ubicaciones != [] do %>
          <.link navigate="/mi-tienda/sedes" style="display: block; text-decoration: none; background: white; border-radius: 18px; margin-bottom: 14px; border: 1.5px solid #186904; box-shadow: 0 3px 14px rgba(24,105,4,0.08); overflow: hidden;">
            <style>
              #mini-mapa-sedes .leaflet-tile-pane { filter: none; }
            </style>
            <div id="mini-mapa-sedes" phx-update="ignore" style="width: 100%; height: 150px; pointer-events: none;"></div>
          </.link>
        <% else %>
          <.link navigate="/mi-tienda/sedes" style="display: block; text-decoration: none; background: #f2f9f2; border-radius: 18px; margin-bottom: 14px; border: 1.5px dashed #b8d4b3; padding: 24px 16px; text-align: center;">
            <p style="font-size: 13px; color: #888; margin: 0; font-family: Poppins, sans-serif;">Todavía no agregaste ninguna sede.</p>
          </.link>
        <% end %>

        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <script>
          const ubicacionesSedes = <%= raw(Jason.encode!(for u <- @ubicaciones, do: %{lat: u.latitude, lng: u.longitude})) %>;
          (function() {
            const el = document.getElementById('mini-mapa-sedes');
            if (!el || ubicacionesSedes.length === 0) return;
            if (el.dataset.mapaInit) return;
            el.dataset.mapaInit = "1";
            const miniMapaSedes = L.map('mini-mapa-sedes', {
              zoomControl: false,
              dragging: false,
              scrollWheelZoom: false,
              doubleClickZoom: false,
              boxZoom: false,
              touchZoom: false,
              attributionControl: false
            });
            L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', { subdomains: 'abcd', maxZoom: 19 }).addTo(miniMapaSedes);
            const iconoCasita = L.divIcon({
              className: '',
              html: '<svg width="30" height="30" viewBox="0 0 40 44" xmlns="http://www.w3.org/2000/svg"><ellipse cx="20" cy="42" rx="14" ry="3" fill="rgba(0,0,0,0.15)"/><path d="M4 24 Q20 -6 36 24 L36 24 Q36 34 26 34 L14 34 Q4 34 4 24 Z" fill="#186904"/><rect x="8" y="20" width="24" height="18" rx="9" fill="white" stroke="#186904" stroke-width="3"/><rect x="15.5" y="26" width="9" height="12" rx="4.5" fill="#186904"/><circle cx="27" cy="27" r="2.4" fill="#186904"/></svg>',
              iconSize: [38, 41.8],
              iconAnchor: [19, 41.8]
            });
            const puntosSedes = ubicacionesSedes.map(u => [u.lat, u.lng]);
            puntosSedes.forEach(p => L.marker(p, { icon: iconoCasita }).addTo(miniMapaSedes));
            if (puntosSedes.length === 1) {
              miniMapaSedes.setView(puntosSedes[0], 14);
            } else {
              miniMapaSedes.fitBounds(puntosSedes, { paddingTopLeft: [20, 45], paddingBottomRight: [20, 20] });
            }
          })();
        </script>
        <.link navigate="/mi-tienda/sedes" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar mis sedes
        </.link>

        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Gestión</p>
        <.link navigate="/mi-tienda/informacion" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Gestionar información
        </.link>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>

        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Estética</p>
        <.link navigate="/mi-tienda/estetica" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Estética de marca
        </.link>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>

        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Suscripción</p>
        <a href="#" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; text-decoration: none; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
          Mis Suscripciones
        </a>
        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>

        <div style="height: 1px; background: #eee; margin: 8px 0 24px;"></div>

        <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Seguridad</p>
        <%= if @brand.pin_hash do %>
          <div style="width: 100%; text-align: center; background-color: #f0f0f0; color: #888; padding: 14px; border-radius: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px; box-sizing: border-box;">
            🔒 Mi PIN (ya configurado)
          </div>
          <p style="font-size: 11px; color: #999; margin: 8px 4px 0; font-family: Poppins, sans-serif; line-height: 1.4;">Si lo olvidaste, contactá a soporte para restablecerlo.</p>
        <% else %>
          <button type="button" onclick="document.getElementById('modal-crear-pin').style.display='flex'" style="width: 100%; text-align: center; background-color: white; color: #186904; padding: 12.5px; border-radius: 16px; border: 1.5px solid #186904; border: none; cursor: pointer; font-family: Poppins, sans-serif; font-weight: 700; font-size: 14px;">
            Mi PIN
          </button>
          <p style="font-size: 11px; color: #999; margin: 8px 4px 0; font-family: Poppins, sans-serif; line-height: 1.4;">Te va a servir para autorizar cambios manuales, como corregir un día de asistencia.</p>
        <% end %>

        <div id="modal-crear-pin" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
          <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
            <div id="pin-paso-inicial">
              <p style="font-size:18px; font-weight:700; color:#186904; margin:0 0 6px; font-family:Poppins,sans-serif;">Crear tu PIN</p>
              <p style="font-size:13px; color:#666; margin:0 0 18px; font-family:Poppins,sans-serif; line-height:1.5;">Se va a generar un PIN de 4 dígitos. Lo vas a poder ver solo esta vez — anotalo en un lugar seguro.</p>
              <button onclick="crearPinAhora()" style="width:100%; background:#186904; color:#fff; border:none; border-radius:14px; padding:12px 0; font-size:14px; font-weight:700; font-family:Poppins,sans-serif; cursor:pointer;">Generar mi PIN</button>
              <button onclick="document.getElementById('modal-crear-pin').style.display='none'" style="width:100%; margin-top:10px; background:none; color:#999; border:none; padding:8px 0; font-size:13px; font-family:Poppins,sans-serif; cursor:pointer;">Cancelar</button>
            </div>
            <div id="pin-paso-mostrado" style="display:none;">
              <p style="font-size:18px; font-weight:700; color:#186904; margin:0 0 6px; font-family:Poppins,sans-serif;">Tu PIN es:</p>
              <p id="pin-valor" style="font-size:36px; font-weight:800; color:#111; letter-spacing:8px; margin:14px 0; font-family:Poppins,sans-serif;"></p>
              <p style="font-size:12px; color:#c0392b; margin:0 0 18px; font-family:Poppins,sans-serif; line-height:1.5; font-weight:600;">⚠ Anotalo ahora. No lo vas a poder volver a ver. Si lo perdés, vas a tener que contactar a soporte.</p>
              <button onclick="document.getElementById('modal-crear-pin').style.display='none'; window.__miTiendaHook.pushEvent('pin_generado', {});" style="width:100%; background:#186904; color:#fff; border:none; border-radius:14px; padding:12px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Ya lo anoté</button>
            </div>
            <p id="pin-error" style="display:none; color:#c0392b; font-size:12px; margin-top:12px; font-family:Poppins,sans-serif;"></p>
          </div>
        </div>

        <script>
          const csrfTokenPin = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
          async function crearPinAhora() {
            const res = await fetch('/mi-tienda/pin/generar', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ _csrf_token: csrfTokenPin })
            });
            const data = await res.json();
            if (data.ok) {
              document.getElementById('pin-paso-inicial').style.display = 'none';
              document.getElementById('pin-paso-mostrado').style.display = 'block';
              document.getElementById('pin-valor').textContent = data.pin;
            } else {
              const err = document.getElementById('pin-error');
              err.textContent = data.mensaje || 'Error al generar el PIN.';
              err.style.display = 'block';
            }
          }
        </script>

      <% else %>
        <p style="font-family: Poppins, sans-serif; color: #666;">No tenés una tienda asignada todavía.</p>
      <% end %>
    </div>
 
    <!-- MODAL CROPPER -->
    <div id="cropper-modal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.85); z-index:9999; align-items:center; justify-content:center;">
      <div style="background:white; border-radius:16px; padding:20px; max-width:600px; width:95%; max-height:95vh; display:flex; flex-direction:column; gap:16px;">
        <h3 style="margin:0; font-size:18px; color:#186904; font-family: Poppins, sans-serif;">Ajustá la imagen</h3>
        <p style="margin:0; font-size:12px; color:#888; font-family: Poppins, sans-serif;">La imagen se sube en alta calidad — la vista previa puede verse pixelada.</p>
        <div style="overflow:hidden; height:40vh;">
          <img id="cropper-img" style="display:block; max-width:100%;"/>
        </div>
        <div style="display:flex; gap:10px; flex-shrink:0;">
          <button onclick="window.dale_confirmarCrop()" style="flex:1; background:#186904; color:white; padding:14px; border:none; border-radius:16px; font-size:15px; font-weight:700; font-family: Poppins, sans-serif; cursor:pointer;">✅ Confirmar</button>
          <button onclick="window.dale_cerrarCropper()" style="flex:1; background:#f0f0f0; color:#333; padding:14px; border:none; border-radius:16px; font-size:15px; font-family: Poppins, sans-serif; cursor:pointer;">Cancelar</button>
        </div>
      </div>
    </div>
 
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.5.13/cropper.min.css"/>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.5.13/cropper.min.js"></script>
 
    <script :type={Phoenix.LiveView.ColocatedHook} name=".MiTiendaHook">
      export default {
        mounted() {
          window.__miTiendaHook = this;

      let gestionModificado = false;
      let esteticaModificado = false;

      function igualarAlturaPreview() {
        const col = document.getElementById('preview-direcciones-col');
        const mapa = document.getElementById('preview-mapa-box');
        if (col && mapa) {
          mapa.style.height = col.offsetHeight + 'px';
        }
      }
      window.addEventListener('load', igualarAlturaPreview);
      setTimeout(igualarAlturaPreview, 300);

      window.actualizarPreviewColor = function(variable, valor) {
        esteticaModificado = true;
        document.getElementById('preview-tienda').style.setProperty('--c-' + variable, valor);
      }

      window.aplicarPaletaRapida = function(principal, fondo, letras, gestion) {
        document.getElementById('color-input-principal').value = principal;
        document.getElementById('color-input-fondo').value = fondo;
        document.getElementById('color-input-letras').value = letras;
        document.getElementById('color-input-gestion').value = gestion;
        actualizarPreviewColor('principal', principal);
        actualizarPreviewColor('fondo', fondo);
        actualizarPreviewColor('letras', letras);
        actualizarPreviewColor('gestion', gestion);
      }

      async function definirEstetica() {
        const btn = document.getElementById('btn-definir-estetica');
        btn.textContent = 'Guardando...'; btn.disabled = true;
        const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
        const formData = new FormData();
        formData.append('_csrf_token', csrfToken);
        formData.append('principal', document.getElementById('color-input-principal').value);
        formData.append('fondo', document.getElementById('color-input-fondo').value);
        formData.append('letras', document.getElementById('color-input-letras').value);
        formData.append('gestion', document.getElementById('color-input-gestion').value);
        const res = await fetch('/mi-tienda/colores', { method: 'POST', body: formData });
        const data = await res.json();
        if (data.ok) {
          esteticaModificado = false;
          btn.textContent = '✅ Aplicado';
          setTimeout(() => { btn.textContent = 'Definir estética'; btn.disabled = false; }, 1500);
        } else {
          btn.textContent = 'Error, reintentar';
          btn.disabled = false;
        }
      }

      // DIRECCIONES
      const addressHidden = document.getElementById('address-hidden');
      const addressFullHidden = document.getElementById('address-full-hidden');
      const container = document.getElementById('direcciones-container');
      if (container) {
        const currentFull = addressFullHidden && addressFullHidden.value ? addressFullHidden.value : (addressHidden ? (addressHidden.value || '') : '');
        const dirs = currentFull.split('|').filter(d => d.trim() !== '');
        if (dirs.length === 0) dirs.push('');
        dirs.forEach(dir => crearInput(dir, true));
      }

      function crearInput(valor, esOriginal) {
        const fila = document.createElement('div');
        fila.style = 'margin-bottom: 8px; position: relative;';

        const wrapper = document.createElement('div');
        wrapper.style = 'display: flex; gap: 8px; align-items: center;';
        const input = document.createElement('input');
        input.type = 'text';
        input.value = valor;
        if (esOriginal && valor.trim() !== '') { input.dataset.original = 'true'; }
        input.placeholder = 'Ej: Av. Corrientes 1234';
        input.autocomplete = 'off';
        input.style = 'flex: 1; padding: 13px 16px; border: 1.5px solid #e0e0e0; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; box-sizing: border-box;';

        const sugerenciasBox = document.createElement('div');
        sugerenciasBox.style = 'display:none; position:absolute; top:100%; left:0; right:0; background:white; border:1.5px solid #e0e0e0; border-radius:14px; margin-top:4px; z-index:50; box-shadow:0 6px 16px rgba(0,0,0,0.1); max-height:220px; overflow-y:auto;';

        let debounceTimer = null;
        input.oninput = () => {
          delete input.dataset.corto;
          actualizarHidden();
          clearTimeout(debounceTimer);
          const q = input.value.trim();
          if (q.length < 4) { sugerenciasBox.style.display = 'none'; return; }
          debounceTimer = setTimeout(() => buscarSugerencias(q, sugerenciasBox, input), 400);
        };
        input.onblur = () => { setTimeout(() => { sugerenciasBox.style.display = 'none'; }, 150); };

        const btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = '✕';
        btn.style = 'background: none; border: none; cursor: pointer; color: #ccc; font-size: 18px;';
        btn.onclick = () => { fila.remove(); actualizarHidden(); };

        wrapper.appendChild(input);
        wrapper.appendChild(btn);
        fila.appendChild(wrapper);
        fila.appendChild(sugerenciasBox);
        container.appendChild(fila);
      }

      function buscarSugerencias(q, box, input) {
        box.innerHTML = '<div style="padding:12px 16px; font-size:13px; color:#999; font-family:Poppins,sans-serif;">Buscando...</div>';
        box.style.display = 'block';
        fetch('/api/buscar-direccion?q=' + encodeURIComponent(q))
          .then(r => r.json())
          .then(data => {
            box.innerHTML = '';
            if (!data.ok || data.sugerencias.length === 0) {
              box.innerHTML = '<div style="padding:12px 16px; font-size:13px; color:#c0392b; font-family:Poppins,sans-serif;">No se encontró esa dirección</div>';
              return;
            }
            data.sugerencias.forEach(s => {
              const item = document.createElement('div');
              item.textContent = s.display_name;
              item.style = 'padding:11px 16px; font-size:13px; color:#333; font-family:Poppins,sans-serif; cursor:pointer; border-bottom:1px solid #f5f5f5;';
              item.onmouseenter = () => { item.style.background = '#f6f6f6'; };
              item.onmouseleave = () => { item.style.background = 'white'; };
              item.onmousedown = (e) => {
                e.preventDefault();
                input.value = s.display_name;
                input.dataset.corto = s.corto || s.display_name;
                box.style.display = 'none';
                actualizarHidden();
              };
              box.appendChild(item);
            });
          })
          .catch(() => {
            box.innerHTML = '<div style="padding:12px 16px; font-size:13px; color:#c0392b; font-family:Poppins,sans-serif;">No se encontró esa dirección</div>';
          });
      }

      window.agregarDireccion = function() { crearInput(''); }

      function actualizarHidden() {
        gestionModificado = true;
        const inputs = container.querySelectorAll('input');
        const largos = Array.from(inputs).map(i => i.value.trim()).filter(v => v !== '');
        const cortos = Array.from(inputs).filter(i => i.value.trim() !== '').map(i => (i.dataset.corto || i.value.trim()));
        addressHidden.value = cortos.join('|');
        addressFullHidden.value = largos.join('|');
      }

      // CATEGORÍAS
      const categoriasHiddenEl = document.getElementById('categorias-hidden');
      let seleccionadas = categoriasHiddenEl && categoriasHiddenEl.value ? categoriasHiddenEl.value.split(',').filter(c => c !== '') : [];

      window.toggleCategoria = function(btn) {
        gestionModificado = true;
        const cat = btn.getAttribute('data-cat');
        if (seleccionadas.includes(cat)) {
          seleccionadas = seleccionadas.filter(c => c !== cat);
          btn.style.background = 'white';
          btn.style.color = '#666';
          btn.style.borderColor = '#e0e0e0';
        } else {
          seleccionadas.push(cat);
          btn.style.background = '#186904';
          btn.style.color = 'white';
          btn.style.borderColor = '#186904';
        }
        categoriasHiddenEl.value = seleccionadas.join(',');
      }

      // CROPPER
      let cropperInstance = null;
      let cropTipo = null;
      let cropBrandId = null;
      let cropOriginalFile = null;
      let cropOriginalImage = null;

      window.abrirCropperFromInput = function(input) {
        const brandId = input.dataset.brandId;
        const tipo = input.dataset.tipo;
        const ax = parseInt(input.dataset.ax);
        const ay = parseInt(input.dataset.ay);
        abrirCropper(input, tipo, ax, ay, brandId);
      }

      function abrirCropper(input, tipo, ax, ay, brandId) {
        const file = input.files[0];
        if (!file) return;
        cropTipo = tipo;
        cropBrandId = brandId;
        cropOriginalFile = file;
        const reader = new FileReader();
        reader.onload = function(e) {
          cropOriginalImage = new Image();
          cropOriginalImage.src = e.target.result;
          const img = document.getElementById('cropper-img');
          img.src = e.target.result;
          const modal = document.getElementById('cropper-modal');
          modal.style.display = 'flex';
          if (cropperInstance) { cropperInstance.destroy(); cropperInstance = null; }
          img.onload = function() {
            cropperInstance = new Cropper(img, {
              aspectRatio: ax / ay,
              viewMode: 1,
              autoCropArea: 0.9,
              movable: true,
              zoomable: true,
              rotatable: false,
              scalable: false,
              checkOrientation: true
            });
          };
        };
        reader.readAsDataURL(file);
        input.value = '';
      }

      window.dale_cerrarCropper = function() {
        const modal = document.getElementById('cropper-modal');
        modal.style.display = 'none';
        if (cropperInstance) { cropperInstance.destroy(); cropperInstance = null; }
        cropOriginalImage = null;
        cropOriginalFile = null;
      };

      window.dale_confirmarCrop = function() {
        if (!cropperInstance || !cropOriginalImage) return;
        const cropData = cropperInstance.getData(true);
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(cropData.width);
        canvas.height = Math.round(cropData.height);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(cropOriginalImage, Math.round(cropData.x), Math.round(cropData.y), Math.round(cropData.width), Math.round(cropData.height), 0, 0, Math.round(cropData.width), Math.round(cropData.height));

        let logoBg = null;
        if (cropTipo === 'logo') {
          try {
            const esquinas = [
              ctx.getImageData(1, 1, 1, 1).data,
              ctx.getImageData(canvas.width - 2, 1, 1, 1).data,
              ctx.getImageData(1, canvas.height - 2, 1, 1).data,
              ctx.getImageData(canvas.width - 2, canvas.height - 2, 1, 1).data
            ];
            let r = 0, g = 0, b = 0;
            esquinas.forEach(px => { r += px[0]; g += px[1]; b += px[2]; });
            r = Math.round(r / 4); g = Math.round(g / 4); b = Math.round(b / 4);
            const hex = c => c.toString(16).padStart(2, '0');
            logoBg = '#' + hex(r) + hex(g) + hex(b);
          } catch (e) { logoBg = null; }
        }

        canvas.toBlob(function(blob) {
          const endpoint = cropTipo === 'logo' ? 'logo' : 'cover';
          const fieldName = cropTipo === 'logo' ? 'logo' : 'cover';
          const formData = new FormData();
          formData.append(fieldName, blob, cropTipo + '.png');
          formData.append('_csrf_token', document.querySelector("meta[name='csrf-token']").getAttribute("content"));
          if (logoBg) { formData.append('logo_bg', logoBg); }
          fetch('/marcas/' + cropBrandId + '/' + endpoint, { method: 'POST', body: formData })
            .then(r => r.json())
            .then(data => {
              if (data.ok) {
                window.dale_cerrarCropper();
                if (window.__miTiendaHook) { window.__miTiendaHook.pushEvent('imagen_actualizada', {}); }
              }
              else alert('Error al subir la imagen');
            });
        }, 'image/png');
      };

      function direccionesInvalidas() {
        const inputs = document.querySelectorAll('#direcciones-container input[type="text"]');
        for (const input of inputs) {
          const valor = input.value.trim();
          if (valor !== '' && !input.dataset.corto && !input.dataset.original) {
            return true;
          }
        }
        return false;
      }

      function recolectarDatosGestion() {
        return {
          name: document.getElementById('input-nombre-tienda').value,
          address: document.getElementById('address-hidden').value,
          address_full: document.getElementById('address-full-hidden').value,
          modalidad: document.getElementById('select-modalidad-tienda').value,
          horario_atencion: document.getElementById('input-horario-tienda').value,
          categorias: document.getElementById('categorias-hidden').value
        };
      }

      function guardarGestion() {
        if (window.__miTiendaHook) {
          window.__miTiendaHook.pushEvent('guardar_gestion', { brand: recolectarDatosGestion() });
        }
      }

      window.validarAntesDeGuardar = function(event) {
        event.preventDefault();

        if (direccionesInvalidas()) {
          document.getElementById('aviso-error-gestion').style.display = 'flex';
          return false;
        }

        const nombre = document.getElementById('input-nombre-tienda').value.trim();
        const horario = document.getElementById('input-horario-tienda').value.trim();
        const direccionesHidden = document.getElementById('address-hidden').value.trim();
        const categoriasHiddenVal = document.getElementById('categorias-hidden').value.trim();

        const faltantes = [];
        if (!nombre) faltantes.push('No pusiste nombre a tu marca');
        if (!direccionesHidden) faltantes.push('No pusiste ninguna dirección');
        if (!categoriasHiddenVal) faltantes.push('No elegiste ninguna categoría');
        if (!horario) faltantes.push('No pusiste horario de atención');

        if (faltantes.length > 0) {
          let html = '';
          faltantes.forEach(f => { html += f + '<br>'; });
          html += '<br>Si continuás así, tu tienda <b>no aparecerá en la búsqueda pública</b> hasta que completes estos datos.';
          document.getElementById('aviso-confirmar-vacios-texto').innerHTML = html;
          document.getElementById('aviso-confirmar-vacios').style.display = 'flex';
          return false;
        }

        gestionModificado = false;
        guardarGestion();
        return false;
      }

      window.continuarGuardadoGestion = function() {
        document.getElementById('aviso-confirmar-vacios').style.display = 'none';
        gestionModificado = false;
        guardarGestion();
      }

      // TODO (pendiente, sesión 23/08/26): la navegación Editor -> Vidriera (esta función,
      // vía push_navigate 'volver_mi_stand') sigue haciendo recarga completa del navegador
      // en vez de navegación fluida de LiveView. Hipótesis de Alan a revisar primero: puede
      // tener que ver con cómo el botón flotante de root.html.heex verifica la URL actual
      // (ver actualizarBotonMiTiendaFlotante, listener de 'phx:page-loading-stop' en
      // root.html.heex) interfiriendo con esta navegación. Vidriera -> Editor (vía
      // <.link navigate>) sí es instantánea. No se pudo diagnosticar más sin ver la consola
      // del navegador en vivo.
      window.intentarVolver = function(event) {
        event.preventDefault();
        if (esteticaModificado) {
          document.getElementById('aviso-salir-texto').textContent = 'Hiciste cambios sin guardar en Estética. ¿Querés guardarlos antes de salir?';
          document.getElementById('aviso-salir-sin-guardar').dataset.seccion = 'estetica';
          document.getElementById('aviso-salir-sin-guardar').style.display = 'flex';
        } else if (gestionModificado) {
          document.getElementById('aviso-salir-texto').textContent = 'Hiciste cambios sin guardar en Gestión. ¿Querés guardarlos antes de salir?';
          document.getElementById('aviso-salir-sin-guardar').dataset.seccion = 'gestion';
          document.getElementById('aviso-salir-sin-guardar').style.display = 'flex';
        } else {
          if (window.__miTiendaHook) {
            window.__miTiendaHook.pushEvent('volver_mi_stand', {});
          } else {
            window.location.href = '/mi-stand';
          }
        }
      }

      window.guardarYSalir = async function() {
        const seccion = document.getElementById('aviso-salir-sin-guardar').dataset.seccion;
        document.getElementById('aviso-salir-sin-guardar').style.display = 'none';
        if (seccion === 'estetica') {
          await definirEstetica();
          window.location.href = '/mi-stand';
        } else {
          gestionModificado = false;
          guardarGestion();
        }
      }

      window.salirSinGuardar = function() {
        document.getElementById('aviso-salir-sin-guardar').style.display = 'none';
        window.location.href = '/mi-stand';
      }
        },
        destroyed() {
          if (window.__miTiendaHook === this) {
            window.__miTiendaHook = null;
          }
          window.intentarVolver = undefined;
          window.actualizarPreviewColor = undefined;
          window.aplicarPaletaRapida = undefined;
          window.agregarDireccion = undefined;
          window.toggleCategoria = undefined;
          window.abrirCropperFromInput = undefined;
          window.dale_cerrarCropper = undefined;
          window.dale_confirmarCrop = undefined;
          window.validarAntesDeGuardar = undefined;
          window.continuarGuardadoGestion = undefined;
          window.guardarYSalir = undefined;
          window.salirSinGuardar = undefined;
        }
      }
    </script>
    """
  end
end

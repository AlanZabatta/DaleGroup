defmodule DaleAppWeb.CajerosLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Accounts
  alias DaleApp.Accounts.Asistencia

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    ranking_puntualidad = calcular_ranking(brand)

    {:ok, assign(socket, brand: brand, cajeros: cajeros, ranking_puntualidad: ranking_puntualidad)}
  end

  def handle_event("toggle_asistencia", _params, socket) do
    brand = socket.assigns.brand
    nuevo_estado = !brand.asistencia_activa

    atributos =
      if nuevo_estado && is_nil(brand.asistencia_activada_en) do
        %{asistencia_activa: true, asistencia_activada_en: DateTime.utc_now() |> DateTime.truncate(:second)}
      else
        %{asistencia_activa: nuevo_estado}
      end

    {:ok, brand_actualizada} =
      brand
      |> Brand.changeset(atributos)
      |> Repo.update()

    ranking_puntualidad = calcular_ranking(brand_actualizada)

    {:noreply, assign(socket, brand: brand_actualizada, ranking_puntualidad: ranking_puntualidad)}
  end

  defp calcular_ranking(nil), do: []
  defp calcular_ranking(%{asistencia_activada_en: nil}), do: []

  defp calcular_ranking(brand) do
    dias_desde_activacion = DateTime.diff(DateTime.utc_now(), brand.asistencia_activada_en, :day)
    ciclo_actual = div(dias_desde_activacion, 30)

    inicio_ciclo =
      brand.asistencia_activada_en
      |> DateTime.add(ciclo_actual * 30 * 86400, :second)
      |> DateTime.to_date()

    fin_ciclo = Date.add(inicio_ciclo, 30)

    from(a in Asistencia,
      where: a.brand_id == ^brand.id and a.fecha >= ^inicio_ciclo and a.fecha < ^fin_ciclo,
      group_by: a.user_id,
      select: {a.user_id, sum(a.puntos)},
      order_by: [desc: sum(a.puntos)],
      limit: 4
    )
    |> Repo.all()
    |> Enum.map(fn {user_id, puntos} -> {Accounts.get_user(user_id), puntos} end)
    |> Enum.reject(fn {cajero, _puntos} -> is_nil(cajero) end)
  end

  defp nombre_corto(cajero) do
    cond do
      cajero.apellido_visible && cajero.apellido_visible != "" ->
        cajero.apellido_visible

      true ->
        apellido_del_name = (cajero.name || "") |> String.split(" ", parts: 2) |> Enum.at(1, "")

        if apellido_del_name != "" do
          apellido_del_name
        else
          (cajero.name || "") |> String.split(" ", parts: 2) |> List.first() || ""
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mis Empleados</p>
      <button type="button" onclick="document.getElementById('modal-qr-empleado').style.display='flex'" style="width: 100%; text-align: center; background-color: #f0f0f0; color: #186904; padding: 12px; border-radius: 16px; margin-bottom: 12px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: none; cursor: pointer;">
        + Agregar nuevo empleado
      </button>

      <a href="/mi-tienda/horarios" style="display: block; text-align: center; background-color: white; color: #186904; padding: 12px; border-radius: 16px; margin-bottom: 20px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
        Ver Horarios
      </a>

      <div id="modal-qr-empleado" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
        <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
          <p style="font-size:18px; font-weight:700; color:#186904; margin:0 0 6px; font-family:Poppins,sans-serif;">Sumá un empleado</p>
          <p style="font-size:13px; color:#666; margin:0 0 18px; font-family:Poppins,sans-serif;">Que escanee este código con su celular</p>
          <div style="background:white; border-radius:16px; padding:16px; display:inline-block; border:1.5px solid #e0e0e0;">
            {raw(EQRCode.encode("https://shawl-stipend-composed.ngrok-free.dev/unirse/#{@brand.id}") |> EQRCode.svg(width: 180))}
          </div>
          <button onclick="document.getElementById('modal-qr-empleado').style.display='none'" style="width:100%; margin-top:18px; background:#186904; color:#fff; border:none; border-radius:14px; padding:12px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Cerrar</button>
        </div>
      </div>

      <%= if Enum.empty?(@cajeros) do %>
        <p style="color: #999; font-family: Poppins, sans-serif; font-size: 14px; text-align: center; padding: 40px 0;">Todavía no tenés empleados asignados.</p>
      <% else %>
        <%
          colores = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
          cajeros_con_color = @cajeros |> Enum.map(fn cajero -> {cajero, Enum.at(colores, rem(cajero.id, length(colores)))} end)
        %>
        <div style="display: flex; flex-wrap: wrap; gap: 12px; justify-content: space-between;">
          <%= for {{cajero, color}, i} <- Enum.with_index(cajeros_con_color) do %>
            <a href={"/mi-tienda/cajeros/#{cajero.id}"} class={if i < 4, do: "cajero-tarjeta-visible", else: "cajero-tarjeta-oculta"} style={"display: #{if i < 4, do: "flex", else: "none"}; width: 47%; flex-direction: column; align-items: center; text-align: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 20px; padding: 18px 10px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); text-decoration: none; box-sizing: border-box;"}>
              <div style={"width: 64px; height: 64px; border-radius: 50%; background: #{color}; display: flex; align-items: flex-end; justify-content: center; margin-bottom: 10px; overflow: hidden; flex-shrink: 0;"}>
                <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <%
                apellido_mostrar = if cajero.apellido_visible && cajero.apellido_visible != "" do
                  cajero.apellido_visible
                else
                  (cajero.name || "") |> String.split(" ", parts: 2) |> Enum.at(1, "")
                end
                nombre_mostrar = if cajero.nombre_visible && cajero.nombre_visible != "" do
                  cajero.nombre_visible
                else
                  (cajero.name || "") |> String.split(" ", parts: 2) |> List.first() || ""
                end
              %>
              <p style="font-size: 16px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= if apellido_mostrar != "", do: apellido_mostrar, else: nombre_mostrar %></p>
              <%= if apellido_mostrar != "" do %>
                <p style="font-size: 13px; color: #999; margin: 2px 0 0; font-family: Poppins, sans-serif;"><%= nombre_mostrar %></p>
              <% end %>
              <%= if cajero.sede && cajero.sede != "" do %>
                <p style="font-size: 11px; color: #888; margin: 4px 0 0; font-family: Poppins, sans-serif;">Sede: <%= cajero.sede %></p>
              <% end %>
              <%= if cajero.zona && cajero.zona != "" do %>
                <p style="font-size: 11px; color: #888; margin: 2px 0 0; font-family: Poppins, sans-serif;">Zona: <%= cajero.zona %></p>
              <% end %>
            </a>
          <% end %>
        </div>

        <%= if length(@cajeros) > 4 do %>
          <button type="button" onclick="document.querySelectorAll('.cajero-tarjeta-oculta').forEach(el => el.style.display = 'flex'); this.style.display = 'none';" style="display: block; width: 100%; margin-top: 16px; background: none; border: 1.5px dashed #e0e0e0; border-radius: 16px; padding: 12px; cursor: pointer; color: #186904; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px;">
            Ver todos ({length(@cajeros)})
          </button>
        <% end %>
      <% end %>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;">
        <p style={"font-size: 13px; font-weight: 700; margin: 0; text-transform: uppercase; letter-spacing: 1px; color: #{if @brand.asistencia_activa, do: "#186904", else: "#bbb"};"}>Asistencia</p>
        <button type="button" phx-click="toggle_asistencia" style={"width: 50px; height: 28px; border-radius: 20px; border: none; cursor: pointer; padding: 3px; display: flex; align-items: center; background: #{if @brand.asistencia_activa, do: "#186904", else: "#ccc"}; justify-content: #{if @brand.asistencia_activa, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
          <div style="width: 22px; height: 22px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
        </button>
      </div>

      <%= if @brand.asistencia_activa do %>
        <div style="background: white; border: 1.5px solid #186904; border-radius: 18px; padding: 18px 16px; box-shadow: 0 3px 12px rgba(24,105,4,0.08);">
          <%= if Enum.empty?(@ranking_puntualidad) do %>
            <div style="display: flex; align-items: flex-end; justify-content: center; gap: 20px; height: 180px; margin-bottom: 8px;">
              <div style="width: 24px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
              <div style="width: 24px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
              <div style="width: 24px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
              <div style="width: 24px; background: #186904; opacity: 0.15; height: 6px; border-radius: 5px 5px 0 0;"></div>
            </div>
            <p style="font-size: 11px; color: #999; margin: 0; text-align: center; font-family: Poppins, sans-serif;">Todavía no hay registros de asistencia</p>
          <% else %>
            <%
              max_puntos = @ranking_puntualidad |> Enum.map(fn {_cajero, puntos} -> puntos end) |> Enum.max()
              colores_mini = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
            %>
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; flex-shrink: 0;">
                <%= for {{cajero, _puntos}, i} <- Enum.with_index(@ranking_puntualidad) do %>
                  <%
                    apellido_mini = nombre_corto(cajero)
                  %>
                  <div style="position: relative; display: flex; flex-direction: column; align-items: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 8px 6px 6px; width: 74px; box-sizing: border-box; box-shadow: 0 2px 6px rgba(0,0,0,0.05);">
                    <%= if i == 0 do %>
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="#f5b301" stroke="#f5b301" style="position: absolute; top: -10px; left: 50%; transform: translateX(-50%); z-index: 2;">
                        <path d="M2 18h20l-2-9-5 4-3-7-3 7-5-4-2 9z"/>
                      </svg>
                    <% end %>
                    <div style={"width: 44px; height: 44px; border-radius: 50%; background: #{Enum.at(colores_mini, rem(cajero.id, length(colores_mini)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; margin-bottom: 6px; flex-shrink: 0;"}>
                      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                        <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                      </svg>
                    </div>
                    <p style="font-size: 11px; font-weight: 700; color: #111; margin: 0; text-align: center; font-family: Poppins, sans-serif; max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= apellido_mini %>
                    </p>
                  </div>
                <% end %>
              </div>
              <div style="flex: 1; position: relative; display: flex; align-items: flex-end; justify-content: center; gap: 10px; height: 180px; padding: 0 8px; border-radius: 12px; background-color: #f7f5ef; background-image: repeating-linear-gradient(to bottom, transparent 0, transparent 29px, #e6e0d2 29px, #e6e0d2 30px); background-position: bottom;">
                <%= for {cajero, puntos} <- @ranking_puntualidad do %>
                  <%
                    altura = max(10, round(puntos / max_puntos * 148))
                  %>
                  <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; width: 34px;">
                    <div title={"#{puntos} pts"} style={"width: 20px; background: #186904; height: #{altura}px; border-radius: 5px 5px 0 0;"}></div>
                    <p style="font-size: 9.5px; font-weight: 600; color: #555; margin: 0; text-align: center; font-family: Poppins, sans-serif; line-height: 1.15; max-width: 34px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <%= nombre_corto(cajero) %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <a href="/mi-tienda/cajeros/asistencia" style="display: block; text-align: center; background-color: white; color: #186904; padding: 11px; border-radius: 14px; margin-top: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; text-decoration: none;">
            Ver detalle
          </a>
        </div>
      <% else %>
        <div style="background: #f5f5f5; border: 1.5px solid #e5e5e5; border-radius: 18px; padding: 22px 16px; text-align: center;">
          <p style="font-size: 12px; color: #aaa; margin: 0; font-family: Poppins, sans-serif;">Activá la asistencia para ver este panel</p>
        </div>
      <% end %>
    </div>
    """
  end
end

defmodule DaleAppWeb.MercadoPuntosLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Brands.Brand
  alias DaleApp.Products

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    premios = if brand, do: Products.listar_premios(brand.id), else: []
    saldo_empleados = if brand, do: calcular_saldo_puntos(brand), else: []
    es_dueño = brand && brand.user_id == user_id

    {:ok,
     assign(socket,
       brand: brand,
       current_user_id: user_id,
       es_dueño: es_dueño,
       premios: premios,
       saldo_empleados: saldo_empleados,
       mostrar_modal_premio: false,
       editando_premio: nil,
       icono_elegido_premio: nil,
       limitar_cantidad_premio: false,
       error_premio: nil,
       premio_a_canjear: nil,
       error_canje: nil,
       canje_resultado: nil
     )}
  end

  def handle_event("abrir_modal_premio", _params, socket) do
    {:noreply,
     assign(socket,
       mostrar_modal_premio: true,
       editando_premio: nil,
       icono_elegido_premio: nil,
       limitar_cantidad_premio: false,
       error_premio: nil
     )}
  end

  def handle_event("toggle_limitar_cantidad_premio", _params, socket) do
    {:noreply, assign(socket, limitar_cantidad_premio: !socket.assigns.limitar_cantidad_premio)}
  end

  def handle_event("editar_premio", %{"id" => id}, socket) do
    premio = Enum.find(socket.assigns.premios, fn p -> p.id == String.to_integer(id) end)

    if premio do
      {:noreply,
       assign(socket,
         mostrar_modal_premio: true,
         editando_premio: premio,
         icono_elegido_premio: premio.icono,
         limitar_cantidad_premio: not is_nil(premio.cantidad_disponible),
         error_premio: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cerrar_modal_premio", _params, socket) do
    {:noreply,
     assign(socket,
       mostrar_modal_premio: false,
       editando_premio: nil,
       icono_elegido_premio: nil,
       limitar_cantidad_premio: false,
       error_premio: nil
     )}
  end

  def handle_event("elegir_icono_premio", %{"icono" => icono}, socket) do
    {:noreply, assign(socket, icono_elegido_premio: icono)}
  end

  def handle_event("cerrar_aviso_premio", _params, socket) do
    {:noreply, assign(socket, error_premio: nil)}
  end

  def handle_event("guardar_premio", params, socket) do
    brand = socket.assigns.brand
    nombre = String.trim(Map.get(params, "nombre", ""))
    puntos_num = case Integer.parse(Map.get(params, "puntos", "")) do
      {n, _} -> n
      :error -> nil
    end

    limitar? = socket.assigns.limitar_cantidad_premio

    cantidad_num =
      if limitar? do
        case Integer.parse(Map.get(params, "cantidad", "")) do
          {n, _} -> n
          :error -> nil
        end
      else
        nil
      end

    cond do
      is_nil(brand) ->
        {:noreply, assign(socket, error_premio: "No se encontró tu marca.")}

      nombre == "" ->
        {:noreply, assign(socket, error_premio: "Te faltó ponerle un nombre al premio.")}

      is_nil(puntos_num) || puntos_num <= 0 ->
        {:noreply, assign(socket, error_premio: "Te faltó poner cuántos puntos cuesta (un número mayor a 0).")}

      limitar? && (is_nil(cantidad_num) || cantidad_num < 0) ->
        {:noreply, assign(socket, error_premio: "Te faltó poner cuántas unidades hay disponibles (0 o más).")}

      true ->
        atributos = %{
          brand_id: brand.id,
          nombre: nombre,
          icono: socket.assigns.icono_elegido_premio,
          puntos_costo: puntos_num,
          cantidad_disponible: cantidad_num
        }

        resultado =
          case socket.assigns.editando_premio do
            nil -> Products.crear_premio(atributos)
            premio -> Products.actualizar_premio(premio, atributos)
          end

        case resultado do
          {:ok, _premio} ->
            premios = Products.listar_premios(brand.id)

            {:noreply,
             assign(socket,
               premios: premios,
               mostrar_modal_premio: false,
               editando_premio: nil,
               icono_elegido_premio: nil,
               error_premio: nil
             )}

          {:error, _changeset} ->
            {:noreply, assign(socket, error_premio: "No se pudo guardar el premio, revisá los datos.")}
        end
    end
  end

  def handle_event("borrar_premio", _params, socket) do
    case socket.assigns.editando_premio do
      nil ->
        {:noreply, socket}

      premio ->
        Products.borrar_premio(premio)
        premios = Products.listar_premios(socket.assigns.brand.id)

        {:noreply,
         assign(socket,
           premios: premios,
           mostrar_modal_premio: false,
           editando_premio: nil,
           icono_elegido_premio: nil,
           error_premio: nil
         )}
    end
  end

  def handle_event("abrir_confirmar_canje", %{"id" => id}, socket) do
    premio = Enum.find(socket.assigns.premios, fn p -> p.id == String.to_integer(id) end)
    {:noreply, assign(socket, premio_a_canjear: premio, error_canje: nil)}
  end

  def handle_event("cancelar_canje", _params, socket) do
    {:noreply, assign(socket, premio_a_canjear: nil, error_canje: nil)}
  end

  def handle_event("cerrar_recibo_canje", _params, socket) do
    {:noreply, assign(socket, canje_resultado: nil)}
  end

  def handle_event("confirmar_canje", _params, socket) do
    brand = socket.assigns.brand
    premio = socket.assigns.premio_a_canjear
    current_user_id = socket.assigns.current_user_id
    es_dueño = socket.assigns.es_dueño
    fecha_ar = NaiveDateTime.utc_now() |> NaiveDateTime.add(-3 * 3600, :second)

    cond do
      is_nil(premio) ->
        {:noreply, socket}

      es_dueño ->
        usuario = Accounts.get_user(current_user_id)

        Products.crear_canje(%{
          brand_id: brand.id,
          user_id: current_user_id,
          premio_id: premio.id,
          premio_nombre: premio.nombre,
          puntos_costo: premio.puntos_costo,
          es_dueño: true
        })

        if premio.cantidad_disponible, do: Products.descontar_stock_premio(premio)
        premios = Products.listar_premios(brand.id)

        {:noreply,
         assign(socket,
           premios: premios,
           premio_a_canjear: nil,
           canje_resultado: %{
             usuario: usuario,
             premio: premio,
             puntos_antes: nil,
             puntos_despues: nil,
             es_dueño: true,
             fecha: fecha_ar
           }
         )}

      true ->
        usuario = Accounts.get_user(current_user_id)
        # El precio ya es el precio final en la moneda del premio. El saldo
        # se mide en ESA categoria, no en la del rol del usuario: asi un
        # multitask gasta del balde correcto segun que este comprando.
        costo_real = premio.puntos_costo
        saldo_disponible = DaleApp.Products.SaldoPuntos.saldo(brand.id, current_user_id, premio.categoria)

        if saldo_disponible < costo_real do
          {:noreply, assign(socket, error_canje: "No tenés puntos suficientes para este premio.")}
        else
          puntos_despues = saldo_disponible - costo_real

          Products.crear_canje(%{
            brand_id: brand.id,
            user_id: current_user_id,
            premio_id: premio.id,
            premio_nombre: premio.nombre,
            puntos_costo: costo_real,
            puntos_antes: saldo_disponible,
            puntos_despues: puntos_despues,
            es_dueño: false
          })

          if premio.cantidad_disponible, do: Products.descontar_stock_premio(premio)
          premios = Products.listar_premios(brand.id)

          {:noreply,
           assign(socket,
             premios: premios,
             premio_a_canjear: nil,
             error_canje: nil,
             canje_resultado: %{
               usuario: usuario,
               premio: %{premio | puntos_costo: costo_real},
               puntos_antes: saldo_disponible,
               puntos_despues: puntos_despues,
               es_dueño: false,
               fecha: fecha_ar
             }
           )}
        end
    end
  end

  # Monedas separadas: el precio de un premio YA es el precio final en su
  # categoria. No hay conversion — antes esto llamaba a costo_para_usuario,
  # el tipo de cambio viejo, que quedo sin uso.
  defp costo_mostrado(_brand, _es_dueño, _current_user_id, precio_original) do
    precio_original
  end

  # Un empleado multitask tiene DOS saldos, no uno: lo que gano vendiendo y
  # lo que gano cargando stock son cosas distintas. Por eso esto ya no
  # devuelve un total — devuelve los dos saldos, y el que sea 0 se puede
  # ocultar en pantalla (cajero y gestor puros siempre tienen uno en 0).
  defp calcular_saldo_puntos(brand) do
    cajeros = Accounts.list_cajeros(brand.id)

    cajeros
    |> Enum.map(fn cajero ->
      {cajero, DaleApp.Products.SaldoPuntos.saldos(brand.id, cajero.id)}
    end)
    |> Enum.sort_by(fn {_cajero, saldos} -> saldos["ventas"] + saldos["gestores"] end, :desc)
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

  defp icono_svg_premio("sol"), do: ~s(<circle cx="12" cy="12" r="4"/><path d="M12 3v1"/><path d="M12 20v1"/><path d="M3 12h1"/><path d="M20 12h1"/><path d="M5.6 5.6l.7.7"/><path d="M17.7 17.7l.7.7"/><path d="M5.6 18.4l.7-.7"/><path d="M17.7 6.3l.7-.7"/>)
  defp icono_svg_premio("manzana"), do: ~s(<path d="M12 7c-4 0 -7 3 -7 7c0 4 3 8 5.5 8c1 0 1.5 -.5 2.5 -.5s1.5 .5 2.5 .5c2.5 0 5.5 -4 5.5 -8c0 -4 -3 -7 -7 -7z"/><path d="M12 7c0 -2 1 -3.5 3 -4"/>)
  defp icono_svg_premio("reloj"), do: ~s(<circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 15"/>)
  defp icono_svg_premio("remera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>)
  defp icono_svg_premio("dalemas"), do: ~s(<text x="12" y="16" text-anchor="middle" font-size="8" font-weight="800" fill="currentColor" stroke="none" font-family="Poppins, sans-serif">Dale+</text>)
  defp icono_svg_premio("persona"), do: ~s(<path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/><path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>)
  defp icono_svg_premio("cash"), do: ~s(<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M7 9v.01"/><path d="M17 15v.01"/>)
  defp icono_svg_premio(_), do: ~s(<circle cx="12" cy="12" r="8"/>)

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <.link navigate="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mercado de puntos</p>

      <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Premios</p>

      <%= if Enum.empty?(@premios) do %>
        <div style="display: flex; flex-wrap: wrap; gap: 12px; justify-content: space-between;">
          <div style="display: flex; width: 47%; flex-direction: column; align-items: center; text-align: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 20px; padding: 18px 10px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); box-sizing: border-box;">
            <div style="width: 64px; height: 64px; border-radius: 50%; background: #e0e0e0; display: flex; align-items: center; justify-content: center; margin-bottom: 10px; overflow: hidden; flex-shrink: 0;">
              <span style="font-size: 28px; color: #999; font-weight: 800;">?</span>
            </div>
            <p style="font-size: 13px; font-weight: 700; color: #999; margin: 0; font-family: Poppins, sans-serif;">No hay ningún premio creado</p>
          </div>
          <div style="display: flex; width: 47%; flex-direction: column; align-items: center; text-align: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 20px; padding: 18px 10px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); box-sizing: border-box;">
            <div style="width: 64px; height: 64px; border-radius: 50%; background: #e0e0e0; display: flex; align-items: center; justify-content: center; margin-bottom: 10px; overflow: hidden; flex-shrink: 0;">
              <span style="font-size: 28px; color: #999; font-weight: 800;">?</span>
            </div>
            <p style="font-size: 13px; font-weight: 700; color: #999; margin: 0; font-family: Poppins, sans-serif;">No hay ningún premio creado</p>
          </div>
        </div>
      <% else %>
        <div style="display: flex; flex-wrap: wrap; gap: 12px; justify-content: space-between;">
          <%= for premio <- @premios do %>
            <div phx-click="abrir_confirmar_canje" phx-value-id={premio.id} style="cursor: pointer; position: relative; display: flex; width: 47%; flex-direction: column; align-items: center; text-align: center; background: white; border: 1.5px solid #f0f0f0; border-radius: 20px; padding: 18px 10px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); box-sizing: border-box;">
              <button type="button" phx-click="editar_premio" phx-value-id={premio.id} style="position: absolute; top: 8px; right: 8px; width: 26px; height: 26px; border-radius: 50%; background: white; border: 1.5px solid #e0e0e0; display: flex; align-items: center; justify-content: center; cursor: pointer; padding: 0;">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M4 20h4L18.5 9.5a2.828 2.828 0 1 0 -4 -4L4 16v4"/>
                  <path d="M13.5 6.5l4 4"/>
                </svg>
              </button>
              <div style="width: 64px; height: 64px; border-radius: 50%; background: #186904; display: flex; align-items: center; justify-content: center; margin-bottom: 10px; overflow: hidden; flex-shrink: 0;">
                <%= if premio.imagen_url do %>
                  <img src={premio.imagen_url} style="width: 100%; height: 100%; object-fit: cover;" />
                <% else %>
                  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: white;">
                    {raw(icono_svg_premio(premio.icono))}
                  </svg>
                <% end %>
              </div>
              <p style="font-size: 13px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= premio.nombre %></p>
              <p style="font-size: 11px; color: #186904; font-weight: 700; margin: 2px 0 0; font-family: Poppins, sans-serif;"><%= costo_mostrado(@brand, @es_dueño, @current_user_id, premio.puntos_costo) %> pts</p>
              <p style="font-size: 10px; color: #999; margin: 2px 0 0; font-family: Poppins, sans-serif;">
                <%= if premio.cantidad_disponible, do: "#{premio.cantidad_disponible} disponibles", else: "Ilimitado" %>
              </p>
            </div>
          <% end %>
        </div>
      <% end %>

      <button type="button" phx-click="abrir_modal_premio" style="width: 100%; text-align: center; background-color: white; color: #186904; padding: 11px; border-radius: 14px; margin-top: 16px; font-family: Poppins, sans-serif; font-weight: 700; font-size: 13px; border: 1.5px solid #186904; cursor: pointer;">
        Crear un premio
      </button>

      <div style="height: 1px; background: #eee; margin: 24px 0 20px;"></div>

      <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0 0 16px; text-transform: uppercase; letter-spacing: 1px;">Puntos de mis empleados</p>

      <%= if Enum.empty?(@saldo_empleados) do %>
        <p style="font-size: 13px; color: #999; text-align: center; padding: 20px 0; font-family: Poppins, sans-serif;">Todavía no tenés empleados cargados.</p>
      <% else %>
        <%
          colores_saldo = ["#E91E8C", "#186904", "#2b2b2b", "#0066cc", "#e67e22", "#8e44ad", "#c0392b", "#16a085"]
        %>
        <%= for {cajero, saldos} <- @saldo_empleados do %>
          <div style="display: flex; align-items: center; justify-content: space-between; background: white; border: 1.5px solid #f0f0f0; border-radius: 14px; padding: 10px 14px; margin-bottom: 8px;">
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style={"width: 36px; height: 36px; border-radius: 50%; background: #{Enum.at(colores_saldo, rem(cajero.id, length(colores_saldo)))}; display: flex; align-items: flex-end; justify-content: center; overflow: hidden; flex-shrink: 0;"}>
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                  <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
                </svg>
              </div>
              <p style="font-size: 13px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= nombre_corto(cajero) %></p>
            </div>
            <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 2px;">
              <%= if saldos["ventas"] > 0 do %>
                <p style="font-size: 13px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= saldos["ventas"] %> pts <span style="font-size: 10px; font-weight: 600; color: #999;">Ventas</span></p>
              <% end %>
              <%= if saldos["gestores"] > 0 do %>
                <p style="font-size: 13px; font-weight: 800; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= saldos["gestores"] %> pts <span style="font-size: 10px; font-weight: 600; color: #999;">Gestores</span></p>
              <% end %>
              <%= if saldos["ventas"] == 0 and saldos["gestores"] == 0 do %>
                <p style="font-size: 13px; font-weight: 800; color: #999; margin: 0; font-family: Poppins, sans-serif;">0 pts</p>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ModalSobreTodo">
        export default {
          mounted() {
            window.__premioFormHook = this;
            window.__modalesAbiertos = (window.__modalesAbiertos || 0) + 1;
            if (window.__modalesAbiertos === 1) {
              const elBoton = document.getElementById("botones-flotantes-app");
              if (elBoton) elBoton.style.display = "none";
              document.body.style.overflow = "hidden";
              document.body.style.touchAction = "none";
            }
          },
          destroyed() {
            window.__modalesAbiertos = Math.max((window.__modalesAbiertos || 1) - 1, 0);
            if (window.__modalesAbiertos === 0) {
              const elBoton = document.getElementById("botones-flotantes-app");
              if (elBoton) elBoton.style.display = "";
              document.body.style.overflow = "";
              document.body.style.touchAction = "";
            }
          }
        }
      </script>

      <%= if @mostrar_modal_premio do %>
        <div id="overlay-modal-premio" phx-hook=".ModalSobreTodo" style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center; padding-top: 66px; padding-bottom: calc(11vh + 10px); box-sizing: border-box;">
          <div style="background: #fff; border-radius: 24px; width: 320px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); max-height: 100%; overflow-y: auto; overflow-x: hidden; touch-action: pan-y;">
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 6px; text-align: center;">
              <%= if @editando_premio, do: "Editar premio", else: "Nuevo premio" %>
            </p>

            <div style="width: 100%; aspect-ratio: 3/4; max-height: 95px; border-radius: 18px; border: 1.5px solid #eef0ea; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); display: flex; align-items: center; justify-content: center; margin: 10px 0; overflow: hidden;">
              <%= if @icono_elegido_premio do %>
                <svg width="35%" height="35%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: #186904;">
                  {raw(icono_svg_premio(@icono_elegido_premio))}
                </svg>
              <% else %>
                <span style="font-size: 12px; color: #bbb; font-family: Poppins, sans-serif;">Elegí un ícono o subí una foto</span>
              <% end %>
            </div>

            <button type="button" disabled style="display: block; width: 100%; box-sizing: border-box; text-align: center; background: #f5f5f5; color: #bbb; border: 1.5px solid #e5e5e5; border-radius: 14px; padding: 10px; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; cursor: not-allowed; margin-bottom: 10px;">
              Subir foto de mi galería (próximamente)
            </button>

            <p style="font-size: 11px; color: #999; text-align: center; margin: 0 0 10px; font-family: Poppins, sans-serif;">o elegí un ícono</p>

            <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; margin-bottom: 12px;">
              <%= for icono <- ["sol", "manzana", "reloj", "remera", "dalemas", "persona", "cash"] do %>
                <button type="button" phx-click="elegir_icono_premio" phx-value-icono={icono} onclick="window.premioModificado = true;" style={"padding: 10px; border-radius: 12px; border: 1.5px solid #{if @icono_elegido_premio == icono, do: "#186904", else: "#e0e0e0"}; background: #{if @icono_elegido_premio == icono, do: "rgba(24,105,4,0.06)", else: "white"}; cursor: pointer; display: flex; align-items: center; justify-content: center;"}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: #186904;">
                    {raw(icono_svg_premio(icono))}
                  </svg>
                </button>
              <% end %>
            </div>

            <form id="form-premio" phx-submit="guardar_premio">
              <input type="text" name="nombre" placeholder="Nombre del premio" autocomplete="off" oninput="window.premioModificado = true;" value={if @editando_premio, do: @editando_premio.nombre, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 8px;" />
              <input type="number" name="puntos" placeholder="Cuántos puntos cuesta" autocomplete="off" oninput="window.premioModificado = true;" value={if @editando_premio, do: @editando_premio.puntos_costo, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 8px;" />

              <div style="display: flex; align-items: center; justify-content: space-between; padding: 4px 2px; margin-bottom: 8px;">
                <p style="font-size: 13px; color: #333; margin: 0; font-family: Poppins, sans-serif;">¿Cantidad limitada?</p>
                <button type="button" phx-click="toggle_limitar_cantidad_premio" onclick="window.premioModificado = true;" style={"width: 42px; height: 24px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; background: #{if @limitar_cantidad_premio, do: "#186904", else: "#ccc"}; justify-content: #{if @limitar_cantidad_premio, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
                  <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3);"></div>
                </button>
              </div>

              <%= if @limitar_cantidad_premio do %>
                <input type="number" name="cantidad" placeholder="Cuántas unidades hay disponibles" autocomplete="off" oninput="window.premioModificado = true;" value={if @editando_premio, do: @editando_premio.cantidad_disponible, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 8px;" />
              <% end %>

              <button type="submit" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
                <%= if @editando_premio, do: "Guardar cambios", else: "Crear premio" %>
              </button>
            </form>

            <%= if @editando_premio do %>
              <button type="button" phx-click="borrar_premio" data-confirm="¿Seguro que querés borrar este premio? No se puede deshacer." style="width: 100%; margin-top: 6px; background: white; color: #c0392b; border: 1.5px solid #c0392b; border-radius: 14px; padding: 11px 0; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
                Borrar premio
              </button>
            <% end %>

            <button type="button" onclick="intentarCancelarPremio()" style="width: 100%; margin-top: 8px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
          </div>
        </div>

        <div id="aviso-salir-premio" style="display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 10000; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 28px; width: 300px; max-width: 85%; padding: 28px 24px 22px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
            <div style="width: 64px; height: 64px; margin: 0 auto 14px; border: 4px solid #186904; border-radius: 50%; display: flex; align-items: center; justify-content: center;">
              <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#186904" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#186904"/></svg>
            </div>
            <p style="font-size: 20px; font-weight: 700; color: #186904; margin: 0 0 12px; font-family: Poppins, sans-serif;">Cambios sin guardar</p>
            <div style="height: 2px; width: 60px; background: #186904; border-radius: 2px; margin: 0 auto 14px;"></div>
            <p style="font-size: 14px; color: #555; margin: 0 0 22px; line-height: 1.5; font-family: Poppins, sans-serif;">Hiciste cambios en este premio. ¿Querés guardarlos antes de salir?</p>
            <div style="display: flex; gap: 10px;">
              <button onclick="guardarYSalirPremio()" style="flex: 1; background: #186904; color: #fff; border: none; border-radius: 14px; padding: 13px 0; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif; cursor: pointer;">Guardar</button>
              <button onclick="noGuardarPremio()" style="flex: 1; background: #fff; color: #186904; border: 2px solid #186904; border-radius: 14px; padding: 11px 0; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif; cursor: pointer;">No guardar</button>
            </div>
          </div>
        </div>

        <div id="premio-avisos-hook" phx-hook=".PremioAvisos" style="display: none;"></div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PremioAvisos">
          export default {
            mounted() {
              window.premioModificado = false;

              window.intentarCancelarPremio = function() {
                if (window.premioModificado) {
                  document.getElementById('aviso-salir-premio').style.display = 'flex';
                } else if (window.__premioFormHook) {
                  window.__premioFormHook.pushEvent('cerrar_modal_premio', {});
                }
              };

              window.noGuardarPremio = function() {
                document.getElementById('aviso-salir-premio').style.display = 'none';
                window.premioModificado = false;
                if (window.__premioFormHook) {
                  window.__premioFormHook.pushEvent('cerrar_modal_premio', {});
                }
              };

              window.guardarYSalirPremio = function() {
                document.getElementById('aviso-salir-premio').style.display = 'none';
                window.premioModificado = false;
                const form = document.getElementById('form-premio');
                if (form) form.requestSubmit();
              };
            }
          }
        </script>
      <% end %>

      <%= if @error_premio do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 10001; display: flex; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 28px; width: 300px; max-width: 85%; padding: 28px 24px 22px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
            <div style="width: 64px; height: 64px; margin: 0 auto 14px; border: 4px solid #c0392b; border-radius: 50%; display: flex; align-items: center; justify-content: center;">
              <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#c0392b" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#c0392b"/></svg>
            </div>
            <p style="font-size: 20px; font-weight: 700; color: #c0392b; margin: 0 0 12px; font-family: Poppins, sans-serif;">Aviso</p>
            <div style="height: 2px; width: 60px; background: #c0392b; border-radius: 2px; margin: 0 auto 14px;"></div>
            <p style="font-size: 14px; color: #555; margin: 0 0 22px; line-height: 1.5; font-family: Poppins, sans-serif;"><%= @error_premio %></p>
            <button type="button" phx-click="cerrar_aviso_premio" style="width: 100%; background: #186904; color: #fff; border: none; border-radius: 14px; padding: 13px 0; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif; cursor: pointer;">Entendido</button>
          </div>
        </div>
      <% end %>

      <%= if @premio_a_canjear do %>
        <div id="overlay-confirmar-canje" phx-hook=".ModalSobreTodo" style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center; padding-top: 74px; padding-bottom: 115px; box-sizing: border-box;">
          <div style="background: #fff; border-radius: 24px; width: 300px; max-width: 88%; padding: 28px 22px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
            <p style="font-size: 17px; font-weight: 700; color: #111; margin: 0 0 8px; font-family: Poppins, sans-serif;">¿Estás seguro que querés canjear "<%= @premio_a_canjear.nombre %>"?</p>
            <p style="font-size: 14px; color: #186904; font-weight: 700; margin: 0 0 20px; font-family: Poppins, sans-serif;">Vale <%= costo_mostrado(@brand, @es_dueño, @current_user_id, @premio_a_canjear.puntos_costo) %> pts</p>

            <%= if @error_canje do %>
              <p style="color: #c0392b; font-size: 13px; margin: 0 0 14px; font-family: Poppins, sans-serif;"><%= @error_canje %></p>
            <% end %>

            <button type="button" phx-click="confirmar_canje" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 13px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer; margin-bottom: 10px;">
              Canjear
            </button>
            <button type="button" phx-click="cancelar_canje" style="width: 100%; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">
              Cancelar
            </button>
          </div>
        </div>
      <% end %>

      <%= if @canje_resultado do %>
        <div id="overlay-recibo-canje" phx-hook=".ModalSobreTodo" style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center; padding-top: 74px; padding-bottom: 115px; box-sizing: border-box;">
          <div style="background: #fff; border-radius: 24px; width: 320px; max-width: 88%; padding: 26px 22px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center; max-height: 100%; overflow-y: auto;">
            <p style="font-size: 13px; font-weight: 700; color: #c0392b; margin: 0 0 4px; text-transform: uppercase; letter-spacing: 0.5px; font-family: Poppins, sans-serif;">📸 Sacá captura de esto</p>
            <p style="font-size: 12px; color: #999; margin: 0 0 20px; font-family: Poppins, sans-serif;">y mostraselo a tu jefe</p>

            <div style="width: 64px; height: 64px; border-radius: 50%; background: #186904; display: flex; align-items: center; justify-content: center; margin: 0 auto 10px;">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="M8 7a4 4 0 1 0 8 0a4 4 0 0 0 -8 0"/>
                <path d="M6 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2"/>
              </svg>
            </div>
            <p style="font-size: 16px; font-weight: 700; color: #111; margin: 0 0 4px; font-family: Poppins, sans-serif;"><%= nombre_corto(@canje_resultado.usuario) %></p>
            <p style="font-size: 12px; color: #999; margin: 0 0 18px; font-family: Poppins, sans-serif;"><%= Calendar.strftime(@canje_resultado.fecha, "%d/%m/%Y %H:%M") %></p>

            <div style="height: 1px; background: #eee; margin: 0 0 16px;"></div>

            <p style="font-size: 13px; color: #999; margin: 0 0 4px; font-family: Poppins, sans-serif;">Canjeó</p>
            <p style="font-size: 16px; font-weight: 700; color: #186904; margin: 0 0 16px; font-family: Poppins, sans-serif;"><%= @canje_resultado.premio.nombre %></p>

            <%= if @canje_resultado.es_dueño do %>
              <p style="font-size: 13px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Canje sin costo (dueño)</p>
            <% else %>
              <div style="display: flex; justify-content: space-around; margin-bottom: 4px;">
                <div>
                  <p style="font-size: 11px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Antes</p>
                  <p style="font-size: 15px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;"><%= @canje_resultado.puntos_antes %> pts</p>
                </div>
                <div>
                  <p style="font-size: 11px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Costo</p>
                  <p style="font-size: 15px; font-weight: 700; color: #c0392b; margin: 0; font-family: Poppins, sans-serif;">-<%= @canje_resultado.premio.puntos_costo %> pts</p>
                </div>
                <div>
                  <p style="font-size: 11px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Ahora</p>
                  <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0; font-family: Poppins, sans-serif;"><%= @canje_resultado.puntos_despues %> pts</p>
                </div>
              </div>
            <% end %>

            <button type="button" phx-click="cerrar_recibo_canje" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer; margin-top: 20px;">
              Listo
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

defmodule DaleAppWeb.NuevoPremioLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products

  def mount(params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil

    editando_premio =
      case params["id"] do
        nil ->
          nil

        id ->
          case Integer.parse(id) do
            {id_int, _} ->
              premio = brand && Repo.get(Products.Premio, id_int)
              if premio && premio.brand_id == brand.id, do: premio, else: nil

            :error ->
              nil
          end
      end

    {:ok,
     assign(socket,
       brand: brand,
       editando_premio: editando_premio,
       icono_elegido_premio: editando_premio && editando_premio.icono,
       limitar_cantidad_premio: editando_premio && not is_nil(editando_premio.cantidad_disponible),
       categoria_elegida_premio: (editando_premio && editando_premio.categoria) || "ventas",
       error_premio: nil
     )}
  end

  def handle_event("elegir_categoria_premio", %{"categoria" => categoria}, socket) do
    {:noreply, assign(socket, categoria_elegida_premio: categoria)}
  end

  def handle_event("toggle_limitar_cantidad_premio", _params, socket) do
    {:noreply, assign(socket, limitar_cantidad_premio: !socket.assigns.limitar_cantidad_premio)}
  end

  def handle_event("elegir_icono_premio", %{"icono" => icono}, socket) do
    {:noreply, assign(socket, icono_elegido_premio: icono)}
  end

  def handle_event("guardar_premio", params, socket) do
    brand = socket.assigns.brand
    nombre = String.trim(Map.get(params, "nombre", ""))
    categoria = socket.assigns.categoria_elegida_premio
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

    parse_puntos = fn campo ->
      case Integer.parse(Map.get(params, campo, "")) do
        {n, _} when n > 0 -> n
        _ -> nil
      end
    end

    base = fn cat, puntos ->
      %{
        brand_id: brand.id,
        nombre: nombre,
        icono: socket.assigns.icono_elegido_premio,
        categoria: cat,
        puntos_costo: puntos,
        cantidad_disponible: cantidad_num
      }
    end

    cond do
      is_nil(brand) ->
        {:noreply, assign(socket, error_premio: "No se encontró tu marca.")}

      nombre == "" ->
        {:noreply, assign(socket, error_premio: "Te faltó ponerle un nombre al premio.")}

      limitar? && (is_nil(cantidad_num) || cantidad_num < 0) ->
        {:noreply, assign(socket, error_premio: "Te faltó poner cuántas unidades hay disponibles (0 o más).")}

      true ->
        puntos_num = parse_puntos.("puntos")

        if is_nil(puntos_num) do
          {:noreply, assign(socket, error_premio: "Te faltó poner cuántos puntos cuesta (un número mayor a 0).")}
        else
          atributos = base.(categoria, puntos_num)

          resultado =
            case socket.assigns.editando_premio do
              nil -> Products.crear_premio(atributos)
              premio -> Products.actualizar_premio(premio, atributos)
            end

          case resultado do
            {:ok, _premio} ->
              {:noreply, push_navigate(socket, to: ~p"/mi-tienda/cajeros/mercado")}

            {:error, _changeset} ->
              {:noreply, assign(socket, error_premio: "No se pudo guardar el premio, revisá los datos.")}
          end
        end
    end
  end

  def handle_event("borrar_premio", _params, socket) do
    case socket.assigns.editando_premio do
      nil ->
        {:noreply, socket}

      premio ->
        Products.borrar_premio(premio)
        {:noreply, push_navigate(socket, to: ~p"/mi-tienda/cajeros/mercado")}
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

  defp categoria_nombre("ventas"), do: "Para vendedores"
  defp categoria_nombre("gestores"), do: "Para gestores"
  defp categoria_nombre("multitask"), do: "Multitask"
  defp categoria_nombre("gerente"), do: "Para gerente"
  defp categoria_nombre(_), do: ""

  defp horizontes_texto(brand, categoria) when is_binary(categoria) do
    h = DaleApp.Products.ReferenciaPrecios.horizontes(brand, categoria)
    aviso = if h.estimado?, do: " (estimado, sin datos aún)", else: ""
    "Referencia: barato #{h.dias_30}pts · medio #{h.dias_60}pts · caro #{h.dias_90}pts#{aviso}"
  end

  defp horizontes_texto(_brand, _categoria), do: ""

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <.link navigate={~p"/mi-tienda/cajeros/mercado"} style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>

      <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px; text-align: center;">
        <%= if @editando_premio, do: "Editar premio", else: "Nuevo premio" %>
      </p>

      <%= if is_nil(@editando_premio) do %>
        <p style="font-size: 13px; color: #999; text-align: center; margin: 0 0 14px; font-family: Poppins, sans-serif;">¿Para quién es el premio?</p>
        <div style="display: flex; gap: 8px; margin-bottom: 20px;">
          <%= for {valor, etiqueta} <- [{"ventas", "Vendedores"}, {"gestores", "Gestores"}, {"multitask", "Multitask"}] do %>
            <button type="button" phx-click="elegir_categoria_premio" phx-value-categoria={valor} style={"flex: 1; padding: 10px 4px; border-radius: 14px; border: 1.5px solid #{if @categoria_elegida_premio == valor, do: "#186904", else: "#e0e0e0"}; background: #{if @categoria_elegida_premio == valor, do: "rgba(24,105,4,0.08)", else: "white"}; color: #{if @categoria_elegida_premio == valor, do: "#186904", else: "#666"}; font-family: Poppins, sans-serif; font-size: 12px; font-weight: 700; cursor: pointer;"}>
              <%= etiqueta %>
            </button>
          <% end %>
        </div>
      <% else %>
        <p style="font-size: 12px; color: #186904; font-weight: 700; text-align: center; margin: 0 0 20px; text-transform: uppercase; letter-spacing: 0.5px; font-family: Poppins, sans-serif;">
          <%= categoria_nombre(@editando_premio.categoria) %>
        </p>
      <% end %>

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
          <button type="button" phx-click="elegir_icono_premio" phx-value-icono={icono} style={"padding: 10px; border-radius: 12px; border: 1.5px solid #{if @icono_elegido_premio == icono, do: "#186904", else: "#e0e0e0"}; background: #{if @icono_elegido_premio == icono, do: "rgba(24,105,4,0.06)", else: "white"}; cursor: pointer; display: flex; align-items: center; justify-content: center;"}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" style="color: #186904;">
              {raw(icono_svg_premio(icono))}
            </svg>
          </button>
        <% end %>
      </div>

      <form id="form-premio" phx-submit="guardar_premio">
        <input type="text" name="nombre" placeholder="Nombre del premio" autocomplete="off" value={if @editando_premio, do: @editando_premio.nombre, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 8px;" />

        <input type="number" name="puntos" placeholder="Cuántos puntos cuesta" autocomplete="off" value={if @editando_premio, do: @editando_premio.puntos_costo, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 4px;" />
        <p style="font-size: 11px; color: #999; margin: 0 0 8px; font-family: Poppins, sans-serif;">
          <%= raw(horizontes_texto(@brand, if(@editando_premio, do: @editando_premio.categoria, else: @categoria_elegida_premio))) %>
        </p>

        <div style="display: flex; align-items: center; justify-content: space-between; padding: 4px 2px; margin-bottom: 8px;">
          <p style="font-size: 13px; color: #333; margin: 0; font-family: Poppins, sans-serif;">¿Cantidad limitada?</p>
          <button type="button" phx-click="toggle_limitar_cantidad_premio" style={"width: 42px; height: 24px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; background: #{if @limitar_cantidad_premio, do: "#186904", else: "#ccc"}; justify-content: #{if @limitar_cantidad_premio, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
            <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3);"></div>
          </button>
        </div>

        <%= if @limitar_cantidad_premio do %>
          <input type="number" name="cantidad" placeholder="Cuántas unidades hay disponibles" autocomplete="off" value={if @editando_premio, do: @editando_premio.cantidad_disponible, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 8px;" />
        <% end %>

        <%= if @error_premio do %>
          <p style="color: #c0392b; font-size: 13px; margin: 0 0 10px; font-family: Poppins, sans-serif;"><%= @error_premio %></p>
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

      <.link navigate={~p"/mi-tienda/cajeros/mercado"} style="display: block; width: 100%; text-align: center; margin-top: 8px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; text-decoration: none;">Cancelar</.link>
    </div>
    """
  end
end

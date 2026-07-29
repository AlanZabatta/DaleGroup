defmodule DaleAppWeb.SedesLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Brands.BrandLocation

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    sedes = if brand, do: listar_sedes(brand.id), else: []
    {:ok, assign(socket, brand: brand, sedes: sedes, editando: nil)}
  end

  defp listar_sedes(brand_id) do
    from(l in BrandLocation, where: l.brand_id == ^brand_id, order_by: [asc: l.id])
    |> Repo.all()
  end

  def handle_event("editar", %{"id" => id}, socket) do
    {:noreply, assign(socket, editando: String.to_integer(id))}
  end

  def handle_event("cancelar", _params, socket) do
    {:noreply, assign(socket, editando: nil)}
  end

  def handle_event("guardar_nombre", %{"id" => id, "nombre" => nombre}, socket) do
    location = Repo.get(BrandLocation, String.to_integer(id))

    if location && location.brand_id == socket.assigns.brand.id do
      location
      |> BrandLocation.changeset(%{nombre: String.trim(nombre)})
      |> Repo.update()
    end

    sedes = listar_sedes(socket.assigns.brand.id)
    {:noreply, assign(socket, sedes: sedes, editando: nil)}
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 6px;">Mis Sedes</p>
      <p style="font-size: 13px; color: #999; margin: 0 0 20px; font-family: Poppins, sans-serif;">Las sedes se crean cargando direcciones en el editor de tu tienda. Acá podés ponerles un nombre.</p>

      <%= if Enum.empty?(@sedes) do %>
        <p style="color: #999; font-family: Poppins, sans-serif; font-size: 14px; text-align: center; padding: 40px 0;">Todavía no tenés sedes cargadas. Agregá direcciones desde el editor de tu tienda.</p>
      <% else %>
        <div style="display: flex; flex-direction: column; gap: 12px;">
          <%= for {sede, i} <- Enum.with_index(@sedes) do %>
            <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 18px; padding: 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06);">
              <div style="display: flex; align-items: flex-start; gap: 12px;">
                <div style="width: 40px; height: 40px; border-radius: 12px; background: rgba(24,105,4,0.1); display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="#186904" xmlns="http://www.w3.org/2000/svg"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
                </div>
                <div style="flex: 1; min-width: 0;">
                  <%= if @editando == sede.id do %>
                    <form phx-submit="guardar_nombre" style="display: flex; flex-direction: column; gap: 8px;">
                      <input type="hidden" name="id" value={sede.id} />
                      <input type="text" name="nombre" value={sede.nombre || ""} placeholder={"Sede #{i + 1}"} autofocus style="width: 100%; box-sizing: border-box; padding: 8px 10px; border: 1.5px solid #186904; border-radius: 10px; font-size: 14px; font-family: Poppins, sans-serif; outline: none;" />
                      <div style="display: flex; gap: 8px;">
                        <button type="submit" style="flex: 1; background: #186904; color: white; border: none; border-radius: 10px; padding: 8px; font-size: 13px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">Guardar</button>
                        <button type="button" phx-click="cancelar" style="flex: 1; background: #f0f0f0; color: #666; border: none; border-radius: 10px; padding: 8px; font-size: 13px; font-weight: 600; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
                      </div>
                    </form>
                  <% else %>
                    <div style="display: flex; align-items: center; gap: 8px;">
                      <p style="font-size: 15px; font-weight: 700; color: #111; margin: 0; font-family: Poppins, sans-serif;">
                        <%= if sede.nombre && sede.nombre != "", do: sede.nombre, else: "Sede #{i + 1}" %>
                      </p>
                      <button type="button" phx-click="editar" phx-value-id={sede.id} style="background: none; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center;">
                        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                      </button>
                    </div>
                    <p style="font-size: 12px; color: #888; margin: 3px 0 0; font-family: Poppins, sans-serif; line-height: 1.3;">
                      <%= sede.address %>
                    </p>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end

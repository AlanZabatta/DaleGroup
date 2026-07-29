defmodule DaleAppWeb.AsistenciaLive do
  use DaleAppWeb, :live_view
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    {:ok, assign(socket, brand: brand, mostrar_info: false)}
  end

  def handle_event("toggle_info", _params, socket) do
    {:noreply, assign(socket, mostrar_info: !socket.assigns.mostrar_info)}
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Asistencia</p>

      <%= if @brand do %>
        <div style="position: relative; background: white; border: 1.5px solid #186904; border-radius: 20px; padding: 20px; box-shadow: 0 3px 14px rgba(24,105,4,0.08); min-height: 220px;">
          <%= if @mostrar_info do %>
            <div style="display: flex; flex-direction: column; height: 100%;">
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
                <p style="font-size: 13px; font-weight: 700; color: #186904; margin: 0; text-transform: uppercase; letter-spacing: 1px;">¿Cómo funciona?</p>
                <button type="button" phx-click="toggle_info" style="background: none; border: none; cursor: pointer; color: #186904; font-size: 18px; font-weight: 700; line-height: 1; padding: 2px 6px;">&#x2715;</button>
              </div>
              <p style="font-size: 13px; color: #444; line-height: 1.6; margin: 0;">
                Imprimí o pegá este código QR en tu local. Cuando un empleado llega, lo escanea con su celular.
                <br/><br/>
                El sistema pide su ubicación en ese momento y verifica que esté cerca de una de tus sedes (dentro de 200 metros). Si está lejos, el fichaje no se registra.
                <br/><br/>
                No guardamos el recorrido ni la ubicación exacta del empleado — solo confirmamos que estaba cerca al momento de fichar.
              </p>
            </div>
          <% else %>
            <div style="display: flex; align-items: center; gap: 16px;">
              <div style="flex-shrink: 0; background: white; border-radius: 14px; padding: 10px; border: 1.5px solid #f0f0f0;">
                {raw(EQRCode.encode("https://shawl-stipend-composed.ngrok-free.dev/fichar/#{@brand.id}") |> EQRCode.svg(width: 130))}
              </div>
              <div style="flex: 1;">
                <p style="font-size: 15px; font-weight: 700; color: #111; margin: 0 0 4px;">Código de fichaje</p>
                <p style="font-size: 12px; color: #888; margin: 0; line-height: 1.4;">Pegalo en tu local para que tus empleados fichen al llegar.</p>
              </div>
              <button type="button" phx-click="toggle_info" style="position: absolute; top: 16px; right: 16px; width: 26px; height: 26px; border-radius: 50%; background: #f0f0f0; border: none; cursor: pointer; color: #186904; font-size: 14px; font-weight: 800; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">?</button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end

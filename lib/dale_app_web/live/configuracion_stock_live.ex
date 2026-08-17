defmodule DaleAppWeb.ConfiguracionStockLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    valor_actual = if brand, do: brand.notificaciones_stock_activas, else: false
    valor_seguridad = if brand, do: brand.notificaciones_seguridad_activas, else: false
    umbral_poco = if brand, do: brand.umbral_poco_stock, else: 4
    umbral_mucho = if brand, do: brand.umbral_mucho_stock, else: 5

    {:ok,
     assign(socket,
       brand: brand,
       notificaciones_stock: valor_actual,
       notificaciones_seguridad: valor_seguridad,
       vapid_public_key: System.get_env("VAPID_PUBLIC_KEY"),
       umbral_poco_stock: umbral_poco,
       umbral_mucho_stock: umbral_mucho,
       ocultar_sin_stock: if(brand, do: brand.ocultar_sin_stock, else: false)
     )}
  end

  def handle_event("cambiar_umbral_poco", %{"valor" => valor}, socket) do
    case Integer.parse(valor) do
      {numero, _} when numero >= 1 ->
        nuevo_mucho = numero + 1

        if socket.assigns.brand do
          socket.assigns.brand
          |> Brand.changeset(%{umbral_poco_stock: numero, umbral_mucho_stock: nuevo_mucho})
          |> Repo.update()
        end

        {:noreply, assign(socket, umbral_poco_stock: numero, umbral_mucho_stock: nuevo_mucho)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cambiar_umbral_mucho", %{"valor" => valor}, socket) do
    case Integer.parse(valor) do
      {numero, _} when numero >= 1 ->
        if socket.assigns.brand do
          socket.assigns.brand
          |> Brand.changeset(%{umbral_mucho_stock: numero})
          |> Repo.update()
        end

        {:noreply, assign(socket, umbral_mucho_stock: numero)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_ocultar_sin_stock", _params, socket) do
    nuevo_valor = !socket.assigns.ocultar_sin_stock

    if socket.assigns.brand do
      socket.assigns.brand
      |> Brand.changeset(%{ocultar_sin_stock: nuevo_valor})
      |> Repo.update()
    end

    {:noreply, assign(socket, ocultar_sin_stock: nuevo_valor)}
  end

  def handle_event("toggle_notificaciones_stock", _params, socket) do
    nuevo_valor = !socket.assigns.notificaciones_stock

    if socket.assigns.brand do
      socket.assigns.brand
      |> Brand.changeset(%{notificaciones_stock_activas: nuevo_valor})
      |> Repo.update()
    end

    {:noreply, assign(socket, notificaciones_stock: nuevo_valor)}
  end

  def handle_event("toggle_notificaciones_seguridad", _params, socket) do
    nuevo_valor = !socket.assigns.notificaciones_seguridad

    if socket.assigns.brand do
      socket.assigns.brand
      |> Brand.changeset(%{notificaciones_seguridad_activas: nuevo_valor})
      |> Repo.update()
    end

    {:noreply, assign(socket, notificaciones_seguridad: nuevo_valor)}
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <.link navigate="/mi-tienda/stock" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Configuración de stock</p>

      <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 16px; padding: 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); margin-bottom: 12px;">
        <p style="font-size: 11px; font-weight: 800; color: #186904; margin: 0 0 14px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;">Configuración de stock</p>

        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;">
          <div style="flex: 1; padding-right: 12px;">
            <p style="font-size: 13.5px; font-weight: 600; color: #111; margin: 0 0 2px; font-family: Poppins, sans-serif;">¿Cuándo es poco stock?</p>
            <p style="font-size: 11.5px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Hasta esta cantidad de unidades</p>
          </div>
          <form phx-change="cambiar_umbral_poco" style="margin: 0; flex-shrink: 0;">
            <input type="number" name="valor" min="1" value={@umbral_poco_stock} style="width: 56px; text-align: center; padding: 8px 4px; border: 1.5px solid #fff6d9; background: #fffbf0; border-radius: 10px; font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #a67c00; outline: none;" />
          </form>
        </div>

        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;">
          <div style="flex: 1; padding-right: 12px;">
            <p style="font-size: 13.5px; font-weight: 600; color: #111; margin: 0 0 2px; font-family: Poppins, sans-serif;">¿A partir de cuánto es mucho stock?</p>
            <p style="font-size: 11.5px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Desde esta cantidad de unidades</p>
          </div>
          <form phx-change="cambiar_umbral_mucho" style="margin: 0; flex-shrink: 0;">
            <input type="number" name="valor" min="1" value={@umbral_mucho_stock} style="width: 56px; text-align: center; padding: 8px 4px; border: 1.5px solid #e6f4e6; background: #f2f9f2; border-radius: 10px; font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #186904; outline: none;" />
          </form>
        </div>

        <div style="display: flex; align-items: center; justify-content: space-between;">
          <div style="flex: 1; padding-right: 12px;">
            <p style="font-size: 13.5px; font-weight: 600; color: #111; margin: 0 0 2px; font-family: Poppins, sans-serif;">¿Cuándo no hay stock?</p>
            <p style="font-size: 11.5px; color: #999; margin: 0; font-family: Poppins, sans-serif;">Este valor no se puede cambiar</p>
          </div>
          <input type="number" value="0" disabled style="width: 56px; text-align: center; padding: 8px 4px; border: 1.5px solid #fdecea; background: #fdf3f2; border-radius: 10px; font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #c0392b; outline: none; opacity: 0.7;" />
        </div>
      </div>

      <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 16px; padding: 14px 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); margin-bottom: 12px;">
        <div style="display: flex; align-items: center; justify-content: space-between;">
          <p style="font-size: 14px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif;">Ocultamiento automático</p>
          <button type="button" phx-click="toggle_ocultar_sin_stock" style={"width: 38px; height: 22px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; flex-shrink: 0; background: #{if @ocultar_sin_stock, do: "#186904", else: "#ccc"}; justify-content: #{if @ocultar_sin_stock, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
            <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
          </button>
        </div>
        <div style="height: 1px; background: #eee; margin: 14px 4px;"></div>
        <p style="font-size: 12px; color: #999; margin: 0; font-family: Poppins, sans-serif; line-height: 1.4;">Si activás esto, los productos que se queden sin stock desaparecen solos de tu tienda virtual hasta que vuelvan a tener unidades disponibles.</p>
      </div>

      <div style="background: white; border: 1.5px solid #f0f0f0; border-radius: 16px; padding: 16px; box-shadow: 0 3px 12px rgba(0,0,0,0.06); margin-bottom: 12px;">
        <p style="font-size: 11px; font-weight: 800; color: #186904; margin: 0 0 14px; text-transform: uppercase; letter-spacing: 1px; font-family: Poppins, sans-serif;">Notificaciones</p>

        <div style="display: flex; align-items: center; justify-content: space-between;">
          <p style="font-size: 14px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif;">Notificaciones de stock</p>
          <button type="button" id="switch-notif-stock" data-activo={to_string(@notificaciones_stock)} onclick="intentarActivarNotifStock()" style={"width: 38px; height: 22px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; flex-shrink: 0; background: #{if @notificaciones_stock, do: "#186904", else: "#ccc"}; justify-content: #{if @notificaciones_stock, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
            <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
          </button>
          <button type="button" id="boton-toggle-notif-stock-real" phx-click="toggle_notificaciones_stock" style="display: none;"></button>
        </div>
        <p style="font-size: 12px; color: #999; margin: 8px 0 0; font-family: Poppins, sans-serif; line-height: 1.4;">Te avisamos si un producto llega a poco stock, se agota, se agota un talle específico, o lleva mucho tiempo sin venderse.</p>

        <div style="height: 1px; background: #eee; margin: 14px 4px;"></div>

        <div style="display: flex; align-items: center; justify-content: space-between;">
          <p style="font-size: 14px; font-weight: 600; color: #111; margin: 0; font-family: Poppins, sans-serif;">Notificaciones de seguridad</p>
          <button type="button" id="switch-notif-seguridad" data-activo={to_string(@notificaciones_seguridad)} onclick="intentarActivarNotifSeguridad()" style={"width: 38px; height: 22px; border-radius: 20px; border: none; cursor: pointer; padding: 2px; display: flex; align-items: center; flex-shrink: 0; background: #{if @notificaciones_seguridad, do: "#186904", else: "#ccc"}; justify-content: #{if @notificaciones_seguridad, do: "flex-end", else: "flex-start"}; transition: background 0.2s;"}>
            <div style="width: 18px; height: 18px; border-radius: 50%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.3); transition: transform 0.2s;"></div>
          </button>
          <button type="button" id="boton-toggle-notif-seguridad-real" phx-click="toggle_notificaciones_seguridad" style="display: none;"></button>
        </div>
        <p style="font-size: 12px; color: #999; margin: 8px 0 0; font-family: Poppins, sans-serif; line-height: 1.4;">Te avisamos si detectamos algo raro: varios productos eliminados seguidos, un precio que bajó o subió mucho de golpe, o un cambio hecho fuera del horario habitual de un empleado.</p>
      </div>

      <div id="modal-permiso-notif-stock" style="display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; align-items: center; justify-content: center;">
        <div style="background: #fff; border-radius: 24px; width: 300px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
          <p style="font-size: 14px; color: #111; margin: 0 0 20px; font-family: Poppins, sans-serif;">Para usar esta función debés permitir las notificaciones</p>
          <div style="display: flex; gap: 10px;">
            <button type="button" onclick="cerrarModalPermisoNotifStock()" style="flex: 1; padding: 10px; border: 1.5px solid #ddd; border-radius: 8px; background: white; cursor: pointer; font-size: 14px; font-family: Poppins, sans-serif;">Cancelar</button>
            <button type="button" onclick="confirmarPermisoNotifStock()" style="flex: 1; padding: 10px; border: none; border-radius: 8px; background: #186904; color: white; cursor: pointer; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif;">Seguir</button>
          </div>
        </div>
      </div>

      <div id="modal-permiso-notif-seguridad" style="display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; align-items: center; justify-content: center;">
        <div style="background: #fff; border-radius: 24px; width: 300px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); text-align: center;">
          <p style="font-size: 14px; color: #111; margin: 0 0 20px; font-family: Poppins, sans-serif;">Para usar esta función debés permitir las notificaciones</p>
          <div style="display: flex; gap: 10px;">
            <button type="button" onclick="cerrarModalPermisoNotifSeguridad()" style="flex: 1; padding: 10px; border: 1.5px solid #ddd; border-radius: 8px; background: white; cursor: pointer; font-size: 14px; font-family: Poppins, sans-serif;">Cancelar</button>
            <button type="button" onclick="confirmarPermisoNotifSeguridad()" style="flex: 1; padding: 10px; border: none; border-radius: 8px; background: #186904; color: white; cursor: pointer; font-size: 14px; font-weight: 600; font-family: Poppins, sans-serif;">Seguir</button>
          </div>
        </div>
      </div>

      <div id="notif-stock-hook" phx-hook=".NotifHookStock" data-vapid={@vapid_public_key} style="display: none;"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NotifHookStock">
        export default {
          mounted() {
            var vapidKey = this.el.getAttribute('data-vapid');

            window.intentarActivarNotifStock = function() {
              var sw = document.getElementById('switch-notif-stock');
              var activo = sw.getAttribute('data-activo') === "true";
              if (activo) {
                document.getElementById('boton-toggle-notif-stock-real').click();
              } else if ('Notification' in window && Notification.permission === 'granted') {
                suscribirPushStock();
              } else {
                document.getElementById('modal-permiso-notif-stock').style.display = 'flex';
              }
            };

            window.cerrarModalPermisoNotifStock = function() {
              document.getElementById('modal-permiso-notif-stock').style.display = 'none';
            };

            function urlBase64ToUint8Array(base64String) {
              var padding = '='.repeat((4 - base64String.length % 4) % 4);
              var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
              var rawData = window.atob(base64);
              var outputArray = new Uint8Array(rawData.length);
              for (var i = 0; i < rawData.length; ++i) {
                outputArray[i] = rawData.charCodeAt(i);
              }
              return outputArray;
            }

            function suscribirPushStock() {
              if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
                document.getElementById('boton-toggle-notif-stock-real').click();
                return;
              }
              navigator.serviceWorker.register('/service-worker.js').then(function(registro) {
                return registro.pushManager.getSubscription().then(function(sub) {
                  if (sub) return sub;
                  return registro.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: urlBase64ToUint8Array(vapidKey)
                  });
                });
              }).then(function(sub) {
                var csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
                return fetch('/push/suscribir', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', 'x-csrf-token': csrfToken },
                  body: JSON.stringify(sub.toJSON())
                });
              }).then(function() {
                document.getElementById('boton-toggle-notif-stock-real').click();
              }).catch(function(err) {
                console.error('Error suscribiendo a push:', err);
              });
            }

            window.confirmarPermisoNotifStock = function() {
              document.getElementById('modal-permiso-notif-stock').style.display = 'none';
              if ('Notification' in window) {
                Notification.requestPermission().then(function(resultado) {
                  if (resultado === 'granted') {
                    suscribirPushStock();
                  }
                });
              } else {
                document.getElementById('boton-toggle-notif-stock-real').click();
              }
            };
          }
        }
      </script>

      <div id="notif-seguridad-hook" phx-hook=".NotifHookSeguridad" data-vapid={@vapid_public_key} style="display: none;"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NotifHookSeguridad">
        export default {
          mounted() {
            var vapidKey = this.el.getAttribute('data-vapid');

            window.intentarActivarNotifSeguridad = function() {
              var sw = document.getElementById('switch-notif-seguridad');
              var activo = sw.getAttribute('data-activo') === "true";
              if (activo) {
                document.getElementById('boton-toggle-notif-seguridad-real').click();
              } else if ('Notification' in window && Notification.permission === 'granted') {
                suscribirPushSeguridad();
              } else {
                document.getElementById('modal-permiso-notif-seguridad').style.display = 'flex';
              }
            };

            window.cerrarModalPermisoNotifSeguridad = function() {
              document.getElementById('modal-permiso-notif-seguridad').style.display = 'none';
            };

            function urlBase64ToUint8Array(base64String) {
              var padding = '='.repeat((4 - base64String.length % 4) % 4);
              var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
              var rawData = window.atob(base64);
              var outputArray = new Uint8Array(rawData.length);
              for (var i = 0; i < rawData.length; ++i) {
                outputArray[i] = rawData.charCodeAt(i);
              }
              return outputArray;
            }

            function suscribirPushSeguridad() {
              if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
                document.getElementById('boton-toggle-notif-seguridad-real').click();
                return;
              }
              navigator.serviceWorker.register('/service-worker.js').then(function(registro) {
                return registro.pushManager.getSubscription().then(function(sub) {
                  if (sub) return sub;
                  return registro.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: urlBase64ToUint8Array(vapidKey)
                  });
                });
              }).then(function(sub) {
                var csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
                return fetch('/push/suscribir', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json', 'x-csrf-token': csrfToken },
                  body: JSON.stringify(sub.toJSON())
                });
              }).then(function() {
                document.getElementById('boton-toggle-notif-seguridad-real').click();
              }).catch(function(err) {
                console.error('Error suscribiendo a push:', err);
              });
            }

            window.confirmarPermisoNotifSeguridad = function() {
              document.getElementById('modal-permiso-notif-seguridad').style.display = 'none';
              if ('Notification' in window) {
                Notification.requestPermission().then(function(resultado) {
                  if (resultado === 'granted') {
                    suscribirPushSeguridad();
                  }
                });
              } else {
                document.getElementById('boton-toggle-notif-seguridad-real').click();
              }
            };
          }
        }
      </script>
    </div>
    """
  end
end

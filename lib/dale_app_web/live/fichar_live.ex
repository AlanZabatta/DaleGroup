defmodule DaleAppWeb.FicharLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Accounts
  alias DaleApp.Accounts.{Asistencia, EmpleadoSede}
  alias DaleApp.Brands.{Brand, BrandLocation, HorarioTrabajo}

  @radio_metros 200

  def mount(%{"brand_id" => brand_id}, session, socket) do
    user_id = session["user_id"]
    user = if user_id, do: Accounts.get_user(user_id), else: nil
    brand = Repo.get(Brand, brand_id)

    es_empleado = user && brand && user.cajero_brand_id == brand.id

    {:ok,
     assign(socket,
       brand: brand,
       user: user,
       es_empleado: es_empleado,
       estado: :consentimiento,
       mensaje: nil,
       mostrar_terminos: false
     )}
  end

  def handle_event("aceptar_consentimiento", _params, socket) do
    {:noreply, assign(socket, estado: :esperando_ubicacion)}
  end

  def handle_event("toggle_terminos", _params, socket) do
    {:noreply, assign(socket, mostrar_terminos: !socket.assigns.mostrar_terminos)}
  end

  def handle_event("ubicacion_recibida", %{"lat" => lat, "lng" => lng}, socket) do
    resultado = procesar_fichaje(socket.assigns.user, socket.assigns.brand, lat, lng)
    {:noreply, assign(socket, estado: elem(resultado, 0), mensaje: elem(resultado, 1))}
  end

  def handle_event("ubicacion_error", %{"tipo" => tipo}, socket) do
    mensaje =
      case tipo do
        "denegado" -> "Le negaste el permiso de ubicación al navegador. Sin eso no podemos confirmar tu fichaje. Activalo en la configuración del navegador e intentá de nuevo."
        "timeout" -> "Tardó demasiado en encontrar tu ubicación. Fijate que tengas el GPS activado e intentá de nuevo."
        "no_disponible" -> "No pudimos obtener tu ubicación en este momento. Probá salir a un lugar con mejor señal."
        _ -> "No pudimos obtener tu ubicación. Activá el GPS y dale permiso al navegador."
      end

    {:noreply, assign(socket, estado: :error, mensaje: mensaje)}
  end

  defp procesar_fichaje(user, brand, lat, lng) do
    sedes_ids =
      from(es in EmpleadoSede, where: es.user_id == ^user.id, select: es.brand_location_id)
      |> Repo.all()

    sedes = from(l in BrandLocation, where: l.id in ^sedes_ids) |> Repo.all()

    sede_cercana =
      sedes
      |> Enum.filter(fn s -> s.latitude && s.longitude end)
      |> Enum.map(fn s -> {s, distancia_metros(lat, lng, s.latitude, s.longitude)} end)
      |> Enum.filter(fn {_s, dist} -> dist <= @radio_metros end)
      |> Enum.sort_by(fn {_s, dist} -> dist end)
      |> List.first()

    case sede_cercana do
      nil ->
        {:fuera_de_rango, "No estás cerca de ninguna de tus sedes. Acercate al local para fichar."}

      {sede, _dist} ->
        hoy = Date.utc_today()
        ya_fichado = from(a in Asistencia, where: a.user_id == ^user.id and a.brand_id == ^brand.id and a.fecha == ^hoy) |> Repo.exists?()

        if ya_fichado do
          {:ya_fichado, "Ya fichaste hoy."}
        else
          puntos = calcular_puntos(user, hoy)

          resultado =
            %Asistencia{}
            |> Asistencia.changeset(%{
              user_id: user.id,
              brand_id: brand.id,
              fecha: hoy,
              hora_marcada: Time.utc_now() |> Time.truncate(:second),
              puntos: puntos,
              brand_location_id: sede.id
            })
            |> Repo.insert()

          otorgar_puntos_por_fichaje(resultado, brand, user, sede, puntos)

          {:exito, "¡Fichaje registrado! Sumaste #{puntos} puntos de puntualidad."}
        end
    end
  end

  # Nunca debe poder tumbar el fichaje: si algo falla aca, el registro de
  # asistencia real ya quedo guardado igual, solo se pierde el punto de logro.
  defp otorgar_puntos_por_fichaje({:ok, asistencia}, brand, user, sede, puntos) do
    DaleApp.Products.RegistroPuntos.registrar(
      brand,
      user,
      "asistencia",
      puntos,
      origen_tipo: "asistencia",
      origen_id: asistencia.id,
      brand_location_id: sede.id
    )
  rescue
    e ->
      require Logger
      Logger.error("Fallo al otorgar puntos por fichaje: " <> Exception.message(e))
  end

  defp otorgar_puntos_por_fichaje(_resultado, _brand, _user, _sede, _puntos), do: :ok

  defp calcular_puntos(user, hoy) do
    dia_semana = dia_en_espanol(hoy)

    horario =
      if user.horario_id, do: Repo.get(HorarioTrabajo, user.horario_id), else: nil

    hora_entrada_esperada =
      cond do
        is_nil(horario) -> nil
        horario.tipo == "especifico" && Map.has_key?(horario.horario_por_dia || %{}, dia_semana) ->
          Map.get(horario.horario_por_dia, dia_semana)["entrada"]
        horario.tipo == "general" && dia_semana in (horario.dias || []) ->
          horario.hora_entrada_general
        true -> nil
      end

    if is_nil(hora_entrada_esperada) do
      1
    else
      [h, m] = String.split(hora_entrada_esperada, ":") |> Enum.map(&String.to_integer/1)
      entrada_esperada = Time.new!(h, m, 0)
      ahora = Time.utc_now()
      diff_min = div(Time.diff(ahora, entrada_esperada, :second), 60)

      cond do
        diff_min <= 0 -> 10
        diff_min <= 5 -> 7
        diff_min <= 10 -> 4
        diff_min <= 15 -> 2
        true -> 1
      end
    end
  end

  defp dia_en_espanol(date) do
    case Date.day_of_week(date) do
      1 -> "lunes"
      2 -> "martes"
      3 -> "miercoles"
      4 -> "jueves"
      5 -> "viernes"
      6 -> "sabado"
      7 -> "domingo"
    end
  end

  defp distancia_metros(lat1, lng1, lat2, lng2) do
    r = 6_371_000
    dlat = deg_a_rad(lat2 - lat1)
    dlng = deg_a_rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(deg_a_rad(lat1)) * :math.cos(deg_a_rad(lat2)) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end

  defp deg_a_rad(deg), do: deg * :math.pi() / 180

  def render(assigns) do
    ~H"""
    <div style="padding: 40px 24px; font-family: Poppins, sans-serif; max-width: 480px; margin: 0 auto; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; background: white;">
      <%= cond do %>
        <% is_nil(@user) -> %>
          <p style="font-size: 16px; color: #666;">Necesitás iniciar sesión para fichar.</p>

        <% !@es_empleado -> %>
          <p style="font-size: 16px; color: #666;">No sos empleado de <%= @brand.name %>.</p>

        <% @estado == :consentimiento -> %>
          <div style="display: flex; flex-direction: column; align-items: center; gap: 16px; width: 100%;">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0;">Fichando en <%= @brand.name %></p>
            <p style="font-size: 13px; color: #555; line-height: 1.6; margin: 0; text-align: left; background: #f7f5ef; border-radius: 14px; padding: 14px 16px;">
              Para registrar tu llegada, vamos a pedirte tu ubicación por única vez. Solo usamos el punto exacto donde estás en este instante para confirmar que llegaste al local — no guardamos tu recorrido ni te rastreamos durante el día.
            </p>
            <button type="button" phx-click="aceptar_consentimiento" style="width: 100%; background: #186904; color: white; border: none; border-radius: 16px; padding: 14px; font-size: 15px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
              Aceptar y fichar mi llegada
            </button>
            <button type="button" phx-click="toggle_terminos" style="background: none; border: none; color: #186904; font-size: 12px; text-decoration: underline; cursor: pointer; font-family: Poppins, sans-serif;">
              Ver términos de uso de tu ubicación
            </button>
            <%= if @mostrar_terminos do %>
              <div style="text-align: left; font-size: 11px; color: #777; line-height: 1.6; background: white; border: 1.5px solid #f0f0f0; border-radius: 12px; padding: 14px;">
                <strong>Uso de datos de ubicación para fichaje.</strong><br/><br/>
                Al tocar "Aceptar", autorizás a <%= @brand.name %> a solicitar tu ubicación GPS en el momento en que fiches tu entrada. Este dato se usa únicamente para verificar que te encontrás dentro de las inmediaciones de una de las sedes de la marca (radio de 200m), como parte del registro de asistencia laboral.<br/><br/>
                No recopilamos tu ubicación en ningún otro momento del día, ni hacemos seguimiento continuo de tus movimientos. El registro guardado incluye la fecha, hora y puntaje de puntualidad de tu fichaje — no las coordenadas exactas de tu ubicación.<br/><br/>
                Podés retirar este consentimiento en cualquier momento hablando con tu empleador. Este texto es informativo y de buena fe; no reemplaza asesoramiento legal profesional sobre normativa laboral y de protección de datos aplicable.
              </div>
            <% end %>
          </div>

        <% @estado == :esperando_ubicacion -> %>
          <div id="ficha-gps" phx-hook=".PedirUbicacion" style="display: flex; flex-direction: column; align-items: center; gap: 16px;">
            <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0;">Buscando tu ubicación...</p>
            <p id="ficha-gps-detalle" style="font-size: 13px; color: #999; margin: 0;">Un momento</p>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".PedirUbicacion">
              export default {
                mounted() {
                  const detalle = document.getElementById("ficha-gps-detalle");
                  const UMBRAL_METROS = 50;
                  const TIEMPO_MAX_MS = 9000;
                  let mejorLectura = null;
                  let watchId = null;
                  let inicio = Date.now();

                  if (!navigator.geolocation) {
                    this.pushEvent("ubicacion_error", { tipo: "no_disponible" });
                    return;
                  }

                  const terminar = () => {
                    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
                    if (mejorLectura) {
                      this.pushEvent("ubicacion_recibida", {
                        lat: mejorLectura.coords.latitude,
                        lng: mejorLectura.coords.longitude
                      });
                    } else {
                      this.pushEvent("ubicacion_error", { tipo: "timeout" });
                    }
                  };

                  const evaluarLectura = (pos) => {
                    if (!mejorLectura || pos.coords.accuracy < mejorLectura.coords.accuracy) {
                      mejorLectura = pos;
                    }
                    if (detalle) {
                      detalle.textContent = "Precisión: " + Math.round(pos.coords.accuracy) + "m";
                    }
                    if (pos.coords.accuracy <= UMBRAL_METROS) {
                      terminar();
                    }
                  };

                  watchId = navigator.geolocation.watchPosition(
                    evaluarLectura,
                    (err) => {
                      if (err.code === 1) {
                        this.pushEvent("ubicacion_error", { tipo: "denegado" });
                        if (watchId !== null) navigator.geolocation.clearWatch(watchId);
                      }
                    },
                    { enableHighAccuracy: true, maximumAge: 0, timeout: TIEMPO_MAX_MS }
                  );

                  setTimeout(() => {
                    if (Date.now() - inicio >= TIEMPO_MAX_MS) terminar();
                  }, TIEMPO_MAX_MS);
                }
              }
            </script>
          </div>

        <% @estado == :exito -> %>
          <div style="display: flex; flex-direction: column; align-items: center; gap: 12px;">
            <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M8 12l3 3 5-6"/></svg>
            <p style="font-size: 17px; font-weight: 700; color: #186904; margin: 0;"><%= @mensaje %></p>
          </div>

        <% @estado == :fuera_de_rango -> %>
          <div style="display: flex; flex-direction: column; align-items: center; gap: 12px;">
            <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="#c0392b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
            <p style="font-size: 15px; color: #c0392b; margin: 0; font-weight: 600;"><%= @mensaje %></p>
          </div>

        <% @estado == :ya_fichado -> %>
          <p style="font-size: 15px; color: #666; margin: 0;"><%= @mensaje %></p>

        <% @estado == :error -> %>
          <div style="display: flex; flex-direction: column; align-items: center; gap: 16px;">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#c0392b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
            <p style="font-size: 14px; color: #c0392b; margin: 0; line-height: 1.5;"><%= @mensaje %></p>
            <button type="button" phx-click="aceptar_consentimiento" style="background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 24px; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
              Reintentar
            </button>
          </div>
      <% end %>
    </div>
    """
  end
end

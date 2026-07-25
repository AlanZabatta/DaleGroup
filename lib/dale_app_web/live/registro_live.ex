defmodule DaleAppWeb.RegistroLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Accounts

  def mount(_params, session, socket) do
    current_user =
      case session["user_id"] do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    auth_pendiente = session["auth_pendiente"]

    {modo, nombre_inicial} =
      if auth_pendiente do
        {"registro", auth_pendiente["name"] || ""}
      else
        {"login", ""}
      end

    username_sugerido = Accounts.generate_username()

    socket =
      socket
      |> assign(:nombre, nombre_inicial)
      |> assign(:username, username_sugerido)
      |> assign(:username_estado, :libre)
      |> assign(:genero, nil)
      |> assign(:ruta_actual, "/registro")
      |> assign(:modo, modo)
      |> assign(:current_user, current_user)
      |> assign(:login_username, "")
      |> assign(:login_username_estado, nil)
      |> assign(:login_email, "")
      |> assign(:login_email_estado, nil)
      |> assign(:auth_pendiente, auth_pendiente)
      |> assign(:error_registro, nil)

    {:ok, socket}
  end

  def handle_event("validar_username", %{"value" => valor}, socket) do
    estado = validar(valor)
    {:noreply, socket |> assign(:username, valor) |> assign(:username_estado, estado)}
  end

  def handle_event("regenerar", _params, socket) do
    nuevo = Accounts.generate_username()
    {:noreply, socket |> assign(:username, nuevo) |> assign(:username_estado, :libre)}
  end

  def handle_event("elegir_genero", %{"genero" => genero}, socket) do
    {:noreply, assign(socket, :genero, genero)}
  end

  def handle_event("cambiar_nombre", %{"value" => valor}, socket) do
    {:noreply, assign(socket, :nombre, valor)}
  end

  def handle_event("cambiar_modo", _params, socket) do
    nuevo_modo = if socket.assigns.modo == "login", do: "registro", else: "login"
    {:noreply, assign(socket, :modo, nuevo_modo)}
  end

  def handle_event("validar_login_username", %{"value" => valor}, socket) do
    estado =
      if String.trim(valor) == "" do
        nil
      else
        Accounts.estado_cuenta(valor)
      end

    {:noreply, socket |> assign(:login_username, valor) |> assign(:login_username_estado, estado)}
  end

  def handle_event("validar_login_email", %{"value" => valor}, socket) do
    estado =
      if String.trim(valor) == "" do
        nil
      else
        Accounts.estado_cuenta_email(valor)
      end

    {:noreply, socket |> assign(:login_email, valor) |> assign(:login_email_estado, estado)}
  end

  def handle_event("registrar", _params, socket) do
    cond do
      is_nil(socket.assigns.auth_pendiente) ->
        {:noreply, socket}

      socket.assigns.username_estado != :libre ->
        {:noreply, assign(socket, :error_registro, "Elegí un nombre de cuenta disponible antes de continuar")}

      is_nil(socket.assigns.genero) ->
        {:noreply, assign(socket, :error_registro, "Elegí una opción de género antes de continuar")}

      true ->
        ap = socket.assigns.auth_pendiente

        base_attrs = %{
          email: ap["email"],
          name: socket.assigns.nombre,
          avatar: ap["avatar"],
          username: socket.assigns.username,
          perfil_config: %{"genero" => socket.assigns.genero}
        }

        resultado =
          case ap["provider"] do
            "google" -> Accounts.create_user_from_google(Map.put(base_attrs, :google_id, ap["uid"]))
            "discord" -> Accounts.create_user_from_discord(Map.put(base_attrs, :discord_id, ap["uid"]))
            _ -> {:error, :proveedor_desconocido}
          end

        case resultado do
          {:ok, user} ->
            {:noreply, redirect(socket, to: ~p"/auth/finalizar?user_id=#{user.id}")}

          {:error, _changeset} ->
            {:noreply, assign(socket, :error_registro, "Hubo un error al crear tu cuenta. Probá de nuevo.")}
        end
    end
  end

  defp validar(valor) do
    cond do
      String.length(valor) < 4 or String.length(valor) > 20 -> :invalido
      Accounts.username_ocupado?(valor) -> :ocupado
      true -> :libre
    end
  end

  defp mensaje_estado_cuenta(:no_existe), do: {"No hay una cuenta registrada a ese nombre de cuenta", "#c0392b"}
  defp mensaje_estado_cuenta(:google), do: {"Cuenta registrada con Google", "#186904"}
  defp mensaje_estado_cuenta(:discord), do: {"Cuenta registrada con Discord", "#186904"}
  defp mensaje_estado_cuenta(:normal), do: {"Cuenta encontrada", "#186904"}
  defp mensaje_estado_cuenta(_), do: nil

  def render(assigns) do
    ~H"""
    <div style="min-height:100vh; background:#fff; max-width:480px; margin:0 auto; font-family:Poppins,sans-serif;">
      <div style="display:flex; align-items:center; justify-content:center; padding:20px 16px; border-bottom:1px solid #eee;">
        <p style="font-size:20px; font-weight:800; color:#186904; margin:0;"><%= if @modo == "login", do: "Iniciar sesión", else: "Regístrate" %></p>
      </div>

      <div style="padding:24px 18px 40px;">
        <%= if @modo == "login" do %>
          <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Nombre de cuenta</p>
          <input type="text" maxlength="20" value={@login_username} phx-keyup="validar_login_username" placeholder="Tu nombre de cuenta"
            style="width:100%; padding:13px 16px; border:1.5px solid #e0e0e0; border-radius:16px; font-family:Poppins,sans-serif; font-size:14px; color:#333; outline:none; box-sizing:border-box; margin-bottom:6px;"/>
          <%= if mensaje = mensaje_estado_cuenta(@login_username_estado) do %>
            <% {texto, color} = mensaje %>
            <p style={"font-size:11px; color:#{color}; margin:0 0 2px;"}><%= texto %></p>
          <% else %>
            <p style="font-size:11px; margin:0 0 2px; height:13px;">&nbsp;</p>
          <% end %>

          <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Gmail</p>
          <input type="email" value={@login_email} phx-keyup="validar_login_email" placeholder="tucorreo@gmail.com"
            style="width:100%; padding:13px 16px; border:1.5px solid #e0e0e0; border-radius:16px; font-family:Poppins,sans-serif; font-size:14px; color:#333; outline:none; box-sizing:border-box; margin-bottom:6px;"/>
          <%= if mensaje = mensaje_estado_cuenta(@login_email_estado) do %>
            <% {texto, color} = mensaje %>
            <p style={"font-size:11px; color:#{color}; margin:0 0 22px;"}><%= texto %></p>
          <% else %>
            <p style="font-size:11px; margin:0 0 22px; height:13px;">&nbsp;</p>
          <% end %>
        <% else %>
          <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Nombre</p>
          <input type="text" value={@nombre} phx-keyup="cambiar_nombre" placeholder="Tu nombre"
            style="width:100%; padding:13px 16px; border:1.5px solid #e0e0e0; border-radius:16px; font-family:Poppins,sans-serif; font-size:14px; color:#333; outline:none; box-sizing:border-box; margin-bottom:22px;"/>

          <%= if @auth_pendiente do %>
            <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Gmail</p>
            <input type="email" value={@auth_pendiente["email"]} readonly
              style="width:100%; padding:13px 16px; border:1.5px solid #e0e0e0; border-radius:16px; font-family:Poppins,sans-serif; font-size:14px; color:#999; background:#f7f7f7; outline:none; box-sizing:border-box; margin-bottom:22px; cursor:not-allowed;"/>
          <% end %>

          <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Nombre de cuenta</p>
          <div style="display:flex; gap:8px; margin-bottom:6px;">
            <input type="text" maxlength="20" value={@username} phx-keyup="validar_username"
              style="flex:1; min-width:0; padding:13px 16px; border:1.5px solid #e0e0e0; border-radius:16px; font-family:Poppins,sans-serif; font-size:14px; color:#333; outline:none; box-sizing:border-box;"/>
            <button phx-click="regenerar" type="button"
              style="background:#186904; color:#fff; border:none; border-radius:16px; padding:0 16px; font-size:18px; cursor:pointer; flex-shrink:0;">&#127922;</button>
          </div>
          <%= case @username_estado do %>
            <% :ocupado -> %>
              <p style="font-size:11px; color:#c0392b; margin:0 0 22px;">Ese nombre ya está ocupado</p>
            <% :invalido -> %>
              <p style="font-size:11px; color:#e67e22; margin:0 0 22px;">Debe tener entre 4 y 20 caracteres</p>
            <% :libre -> %>
              <p style="font-size:11px; color:#186904; margin:0 0 22px;">Disponible</p>
          <% end %>

          <p style="font-size:13px; font-weight:600; color:#186904; margin:0 0 8px;">Género</p>
          <div style="display:flex; gap:8px; margin-bottom:28px;">
            <div phx-click="elegir_genero" phx-value-genero="hombre"
              style={"flex:1; display:flex; flex-direction:column; align-items:center; gap:6px; padding:14px 0; border:2px solid #{if @genero == "hombre", do: "#186904", else: "#e0e0e0"}; border-radius:16px; cursor:pointer; transition:all 0.2s;"}>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#2196F3" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="10" cy="14" r="5"/><line x1="19" y1="5" x2="13.6" y2="10.4"/><polyline points="15 5 19 5 19 9"/></svg>
              <span style="font-size:12px; color:#555;">Hombre</span>
            </div>
            <div phx-click="elegir_genero" phx-value-genero="mujer"
              style={"flex:1; display:flex; flex-direction:column; align-items:center; gap:6px; padding:14px 0; border:2px solid #{if @genero == "mujer", do: "#186904", else: "#e0e0e0"}; border-radius:16px; cursor:pointer; transition:all 0.2s;"}>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#E91E8C" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="5"/><line x1="12" y1="13" x2="12" y2="21"/><line x1="9" y1="18" x2="15" y2="18"/></svg>
              <span style="font-size:12px; color:#555;">Mujer</span>
            </div>
            <div phx-click="elegir_genero" phx-value-genero="otro"
              style={"flex:1; display:flex; flex-direction:column; align-items:center; gap:6px; padding:14px 0; border:2px solid #{if @genero == "otro", do: "#186904", else: "#e0e0e0"}; border-radius:16px; cursor:pointer; transition:all 0.2s;"}>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#888" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/></svg>
              <span style="font-size:12px; color:#555;">Prefiero no decir</span>
            </div>
          </div>
        <% end %>

        <%= if @auth_pendiente do %>
          <%= if @error_registro do %>
            <p style="font-size:12px; color:#c0392b; text-align:center; margin:0 0 12px;"><%= @error_registro %></p>
          <% end %>
          <button phx-click="registrar" type="button"
            style="width:100%; padding:14px 0; background:#186904; color:#fff; border:none; border-radius:16px; font-size:15px; font-weight:700; font-family:Poppins,sans-serif; cursor:pointer;">Listo</button>
        <% else %>
          <div style="display:flex; align-items:center; gap:10px; margin-bottom:20px;">
            <div style="flex:1; height:1px; background:#eee;"></div>
            <span style="font-size:11px; color:#aaa;">Iniciar sesión con</span>
            <div style="flex:1; height:1px; background:#eee;"></div>
          </div>

          <a href="/auth/google" style="display:flex; align-items:center; justify-content:center; gap:10px; width:100%; padding:13px 0; border:1.5px solid #e0e0e0; border-radius:16px; text-decoration:none; margin-bottom:10px; box-sizing:border-box;">
            <svg width="18" height="18" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
            <span style="font-size:14px; font-weight:600; color:#333;">Continuar con Google</span>
          </a>

          <a href="/auth/discord" style="display:flex; align-items:center; justify-content:center; gap:10px; width:100%; padding:13px 0; border:1.5px solid #e0e0e0; border-radius:16px; text-decoration:none; box-sizing:border-box;">
            <svg width="18" height="18" viewBox="0 0 127.14 96.36">
              <path fill="#5865F2" d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/>
            </svg>
            <span style="font-size:14px; font-weight:600; color:#333;">Continuar con Discord</span>
          </a>
          <p style="text-align:center; font-size:13px; color:#666; margin:18px 0 0;">
            <%= if @modo == "login" do %>
              ¿No tienes cuenta? <span phx-click="cambiar_modo" style="color:#186904; font-weight:700; cursor:pointer;">Créate una aquí</span>
            <% else %>
              ¿Ya tienes cuenta? <span phx-click="cambiar_modo" style="color:#186904; font-weight:700; cursor:pointer;">Inicia sesión aquí</span>
            <% end %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

end

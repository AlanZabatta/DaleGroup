defmodule DaleAppWeb.MiTiendaEsteticaLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    {:ok, assign(socket, brand: brand)}
  end

  def handle_event("volver_mi_tienda", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/mi-tienda")}
  end

  def handle_event("imagen_actualizada", _params, socket) do
    brand = Repo.get!(Brand, socket.assigns.brand.id)
    {:noreply, assign(socket, brand: brand)}
  end

  def render(assigns) do
    pv_principal = (assigns.brand.colores && assigns.brand.colores["principal"]) || "#186904"
    pv_fondo = (assigns.brand.colores && assigns.brand.colores["fondo"]) || "#ffffff"
    pv_letras = (assigns.brand.colores && assigns.brand.colores["letras"]) || "#1a1a1a"
    pv_gestion = (assigns.brand.colores && assigns.brand.colores["gestion"]) || "#ffffff"

    assigns =
      assigns
      |> assign(:pv_principal, pv_principal)
      |> assign(:pv_fondo, pv_fondo)
      |> assign(:pv_letras, pv_letras)
      |> assign(:pv_gestion, pv_gestion)

    ~H"""
    <div id="aviso-salir-estetica" style="display:none; position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,0.45); z-index:9999; align-items:center; justify-content:center;">
      <div style="background:#fff; border-radius:28px; width:300px; max-width:85%; padding:28px 24px 22px; box-shadow:0 12px 40px rgba(0,0,0,0.25); text-align:center;">
        <div style="width:64px; height:64px; margin:0 auto 14px; border:4px solid #186904; border-radius:50%; display:flex; align-items:center; justify-content:center;">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none"><line x1="12" y1="7" x2="12" y2="14" stroke="#186904" stroke-width="3.5" stroke-linecap="round"/><circle cx="12" cy="18.5" r="1.8" fill="#186904"/></svg>
        </div>
        <p style="font-size:20px; font-weight:700; color:#186904; margin:0 0 12px; font-family:Poppins,sans-serif;">Cambios sin guardar</p>
        <div style="height:2px; width:60px; background:#186904; border-radius:2px; margin:0 auto 14px;"></div>
        <p style="font-size:14px; color:#555; margin:0 0 22px; line-height:1.5; font-family:Poppins,sans-serif;">Hiciste cambios sin guardar en Estética. ¿Querés guardarlos antes de salir?</p>
        <div style="display:flex; gap:10px;">
          <button onclick="guardarYSalirEstetica()" style="flex:1; background:#186904; color:#fff; border:none; border-radius:14px; padding:13px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Guardar</button>
          <button onclick="salirSinGuardarEstetica()" style="flex:1; background:#fff; color:#186904; border:2px solid #186904; border-radius:14px; padding:11px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">No guardar</button>
        </div>
      </div>
    </div>

    <div id="mi-tienda-estetica-root" phx-hook=".EsteticaHook" style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="#" onclick="intentarVolverEstetica(event)" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Estética de marca</p>

      <div style="margin-bottom: 24px;">
        <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0 0 12px;">Vista previa</p>
        <div style="max-width: 100%; overflow: hidden; border-radius: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.12); border: 1px solid #f0f0f0;">
          <div id="preview-tienda" style={"zoom: 0.72; width: 380px; margin: 0 auto; --c-principal:#{@pv_principal}; --c-fondo:#{@pv_fondo}; --c-letras:#{@pv_letras}; --c-gestion:#{@pv_gestion};"}>
            <div style={"position: relative; width: 100%; aspect-ratio: 16/9; overflow: hidden; border-radius: 0 0 28px 28px; background-color: var(--c-principal);#{if @brand.cover_image, do: " background-image: url('#{@brand.cover_image}'); background-size: cover; background-position: center;", else: ""}"}>
              <div style="position: absolute; inset: 0; background: linear-gradient(to bottom, rgba(0,0,0,0) 35%, rgba(0,0,0,0.55) 100%);"></div>
            </div>
            <div style="padding: 0 16px; margin-top: -70px; position: relative; z-index: 5;">
              <div style="position: relative; display: inline-block;">
                <div style="border: 1.5px solid #f0f0f0; border-radius: 16px; width: 220px; height: 140px; display: flex; align-items: center; justify-content: center; background: white; overflow: hidden; box-shadow: 0 6px 20px rgba(0,0,0,0.12);">
                  <%= if @brand.logo do %>
                    <img src={@brand.logo} style="width: 100%; height: 100%; object-fit: contain; padding: 16px; box-sizing: border-box; display: block;"/>
                  <% else %>
                    <span style="color: #ccc; font-size: 14px;">Logo</span>
                  <% end %>
                </div>
                <div style="position: absolute; bottom: -18px; right: -20px; background-color: var(--c-principal); color: var(--c-gestion); font-size: 34px; font-weight: 900; padding: 10px 16px; line-height: 1; font-family: 'Abril Fatface', cursive; border-radius: 16px; box-shadow: 0 6px 16px rgba(0,0,0,0.25);">
                  30%
                </div>
              </div>
            </div>
            <div style="padding: 16px; margin-top: 16px;">
              <div style="background: var(--c-fondo); border-radius: 20px; padding: 18px; box-shadow: 0 4px 18px rgba(0,0,0,0.07); border: 1px solid #f2f2f2;">
                <h1 style="font-family: 'Abril Fatface', cursive; font-size: 26px; color: var(--c-letras); margin: 0; font-weight: 400; line-height: 1.1;"><%= @brand.name %></h1>
                <%= if @brand.categorias && @brand.categorias != [] do %>
                  <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px;">
                    <%= for cat <- @brand.categorias do %>
                      <span style="background: rgba(0,0,0,0.06); color: var(--c-principal); font-size: 11px; font-weight: 600; padding: 5px 11px; border-radius: 20px; font-family: 'Noto Sans', sans-serif;"><%= cat %></span>
                    <% end %>
                  </div>
                <% end %>
                <div style="margin-top: 14px; padding-top: 14px; border-top: 1px solid #f2f2f2; display: flex; align-items: stretch; gap: 12px;">
                  <div id="preview-direcciones-col" style="flex: 1; display: flex; flex-direction: column; justify-content: flex-start; gap: 6px;">
                    <%= if @brand.address do %>
                      <%= for dir <- String.split(@brand.address, "|") do %>
                        <div style="display: flex; align-items: center; gap: 8px;">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="var(--c-principal)" xmlns="http://www.w3.org/2000/svg" style="flex-shrink:0;"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
                          <span style="font-size: 13px; color: var(--c-letras); font-family: 'Noto Sans', sans-serif; font-weight: 500;"><%= String.trim(dir) %></span>
                        </div>
                      <% end %>
                    <% else %>
                      <div style="display: flex; align-items: center; gap: 8px;">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="var(--c-principal)" xmlns="http://www.w3.org/2000/svg" style="flex-shrink:0;"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
                        <span style="font-size: 13px; color: var(--c-letras); font-family: 'Noto Sans', sans-serif; font-weight: 500;">Tu dirección acá</span>
                      </div>
                    <% end %>
                    <%= if @brand.horario_atencion && @brand.horario_atencion != "" do %>
                      <div style="display: flex; align-items: center; gap: 8px; margin-top: 2px;">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--c-principal)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" style="flex-shrink:0;"><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 15"/></svg>
                        <span style="font-size: 13px; color: var(--c-letras); font-family: 'Noto Sans', sans-serif; font-weight: 500;"><%= @brand.horario_atencion %></span>
                      </div>
                    <% end %>
                  </div>
                  <div id="preview-mapa-box" style="width: 140px; flex-shrink: 0; position: relative; border-radius: 16px; overflow: hidden; border: 1.5px solid #f0f0f0; background: linear-gradient(135deg, #cfe8d8 0%, #b8dcc4 40%, #a8d4b8 100%); display: flex; align-items: center; justify-content: center;">
                    <svg width="140" height="140" viewBox="0 0 140 140" style="position:absolute; top:0; left:0; opacity:0.5;" xmlns="http://www.w3.org/2000/svg">
                      <path d="M0,40 Q40,20 70,45 T140,35" stroke="white" stroke-width="4" fill="none"/>
                      <path d="M0,90 Q50,70 90,95 T140,80" stroke="white" stroke-width="5" fill="none"/>
                      <path d="M25,0 Q40,60 20,140" stroke="white" stroke-width="3" fill="none"/>
                      <path d="M110,0 Q95,70 115,140" stroke="white" stroke-width="3" fill="none"/>
                    </svg>
                    <svg width="26" height="26" viewBox="0 0 24 24" fill="var(--c-principal)" xmlns="http://www.w3.org/2000/svg" style="position:relative; z-index:2; filter:drop-shadow(0 2px 3px rgba(0,0,0,0.3));"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
                  </div>
                </div>
              </div>
            </div>
            <div style="padding: 0 16px 16px;">
              <div style="background: var(--c-principal); border-radius: 18px; padding: 20px; box-shadow: 0 3px 12px rgba(0,0,0,0.08);">
                <div style="width: 100%; background-color: white; color: var(--c-principal); padding: 15px; border-radius: 16px; font-size: 15px; font-weight: 800; text-align: center; font-family: 'Noto Sans', sans-serif; box-sizing: border-box;">
                  USAR BENEFICIO
                </div>
                <div style="margin-top: 10px; text-align: center;">
                  <span style="color: var(--c-gestion); opacity: 0.85; font-size: 12px; font-family: 'Noto Sans', sans-serif; font-style: italic;">Mostrar al vendedor</span>
                </div>
              </div>
            </div>
            <div style="padding: 0 16px 16px; display: flex; gap: 10px;">
              <div style="flex: 1; display: flex; flex-direction: column; border-radius: 16px; overflow: hidden; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: var(--c-fondo);">
                <div style="aspect-ratio: 3/4; background: #f5f5f5; display: flex; align-items: center; justify-content: center;">
                  <span style="font-size: 40px; color: #111; font-weight: 800;">?</span>
                </div>
                <div style="padding: 8px 10px;">
                  <p style="font-size: 12px; color: #888; margin: 0;">Producto</p>
                  <p style="font-size: 15px; font-weight: 700; color: var(--c-principal); margin: 0;">$0000</p>
                </div>
              </div>
              <div style="flex: 1; display: flex; flex-direction: column; border-radius: 16px; overflow: hidden; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: var(--c-fondo);">
                <div style="aspect-ratio: 3/4; background: #f5f5f5; display: flex; align-items: center; justify-content: center;">
                  <span style="font-size: 40px; color: #111; font-weight: 800;">?</span>
                </div>
                <div style="padding: 8px 10px;">
                  <p style="font-size: 12px; color: #888; margin: 0;">Producto</p>
                  <p style="font-size: 15px; font-weight: 700; color: var(--c-principal); margin: 0;">$0000</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div style="margin-bottom: 24px;">
        <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0 0 12px;">Colores de tu tienda</p>
        <div style="display:flex; flex-direction:column; gap:12px;">
          <div style="display:flex; align-items:center; justify-content:space-between;">
            <span style="font-size:13px; color:#333; font-family:Poppins,sans-serif;">Color principal</span>
            <input type="color" id="color-input-principal" value={@pv_principal} oninput="actualizarPreviewColor('principal', this.value)" style="width:40px; height:40px; border:none; border-radius:8px; cursor:pointer;"/>
          </div>
          <div style="display:flex; align-items:center; justify-content:space-between;">
            <span style="font-size:13px; color:#333; font-family:Poppins,sans-serif;">Color de fondo</span>
            <input type="color" id="color-input-fondo" value={@pv_fondo} oninput="actualizarPreviewColor('fondo', this.value)" style="width:40px; height:40px; border:none; border-radius:8px; cursor:pointer;"/>
          </div>
          <div style="display:flex; align-items:center; justify-content:space-between;">
            <span style="font-size:13px; color:#333; font-family:Poppins,sans-serif;">Color de letras</span>
            <input type="color" id="color-input-letras" value={@pv_letras} oninput="actualizarPreviewColor('letras', this.value)" style="width:40px; height:40px; border:none; border-radius:8px; cursor:pointer;"/>
          </div>
          <div style="display:flex; align-items:center; justify-content:space-between;">
            <span style="font-size:13px; color:#333; font-family:Poppins,sans-serif;">Color de gestión</span>
            <input type="color" id="color-input-gestion" value={@pv_gestion} oninput="actualizarPreviewColor('gestion', this.value)" style="width:40px; height:40px; border:none; border-radius:8px; cursor:pointer;"/>
          </div>
        </div>
        <div style="display:flex; gap:8px; margin-top:16px;">
          <button type="button" onclick="aplicarPaletaRapida('#186904','#ffffff','#1a1a1a','#ffffff')" style="flex:1; padding:10px; border-radius:12px; border:1.5px solid #e0e0e0; background:white; cursor:pointer; font-size:11px; font-family:Poppins,sans-serif;">🟢 Verde/Blanco</button>
          <button type="button" onclick="aplicarPaletaRapida('#000000','#ffffff','#111111','#ffffff')" style="flex:1; padding:10px; border-radius:12px; border:1.5px solid #e0e0e0; background:white; cursor:pointer; font-size:11px; font-family:Poppins,sans-serif;">⚫ Negro/Blanco</button>
          <button type="button" onclick="aplicarPaletaRapida('#E91E8C','#ffffff','#1a1a1a','#ffffff')" style="flex:1; padding:10px; border-radius:12px; border:1.5px solid #e0e0e0; background:white; cursor:pointer; font-size:11px; font-family:Poppins,sans-serif;">🌸 Rosa/Blanco</button>
        </div>
        <p style="font-size:11px; color:#999; margin:12px 0 0; line-height:1.4;">Tené en cuenta que la estética de tu marca define tu convertibilidad de ventas. ¡Esforzate!</p>
      </div>

      <div style="margin-bottom: 22px;">
        <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0 0 8px;">Logo de la tienda</p>
        <% logo_fondo = (@brand.colores && @brand.colores["logo_fondo"]) || "#f5f5f5" %>
        <label style={"display: block; position: relative; width: 100%; height: 180px; border-radius: 16px; overflow: hidden; cursor: pointer; background: #{logo_fondo}; border: 1.5px solid #e0e0e0;"}>
          <%= if @brand.logo do %>
            <img src={@brand.logo} style="width: 100%; height: 100%; object-fit: contain; padding: 20px; box-sizing: border-box; display: block;"/>
          <% else %>
            <div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ccc" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>
            </div>
          <% end %>
          <div style={"position: absolute; bottom: 10px; right: 10px; width: 40px; height: 40px; background: #{@pv_principal}; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.25);"}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>
          </div>
          <input type="file" accept="image/*" style="display:none;" data-brand-id={"#{@brand.id}"} data-tipo="logo" data-ax="2" data-ay="1" onchange="abrirCropperFromInput(this)" />
        </label>
      </div>

      <div style="margin-bottom: 22px;">
        <p style="font-size: 13px; font-weight: 600; color: #186904; margin: 0 0 8px;">Foto de publicación</p>
        <p style="font-size: 12px; color: #888; margin: 0 0 10px; font-family: Poppins, sans-serif;">Esta foto aparece en la página principal como card de tu marca.</p>
        <label style="display: block; position: relative; width: 100%; aspect-ratio: 16/7; border-radius: 16px; overflow: hidden; cursor: pointer; background: #f5f5f5; border: 1.5px solid #e0e0e0;">
          <%= if @brand.cover_image do %>
            <img src={@brand.cover_image} style="width: 100%; height: 100%; object-fit: cover; display: block;"/>
          <% else %>
            <div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ccc" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>
            </div>
          <% end %>
          <div style={"position: absolute; bottom: 10px; right: 10px; width: 40px; height: 40px; background: #{@pv_principal}; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.25);"}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>
          </div>
          <input type="file" accept="image/*" style="display:none;" data-brand-id={"#{@brand.id}"} data-tipo="cover" data-ax="16" data-ay="7" onchange="abrirCropperFromInput(this)" />
        </label>
      </div>

      <button type="button" onclick="definirEstetica()" id="btn-definir-estetica" style="width:100%; margin-bottom: 22px; background:#186904; color:white; padding:14px 0; border:none; border-radius:16px; cursor:pointer; font-size:15px; font-weight:700; font-family:Poppins,sans-serif;">
        Definir estética
      </button>
    </div>

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

    <script :type={Phoenix.LiveView.ColocatedHook} name=".EsteticaHook">
      export default {
        mounted() {
          window.__esteticaHook = this;
          let esteticaModificado = false;

          function igualarAlturaPreview() {
            const col = document.getElementById('preview-direcciones-col');
            const mapa = document.getElementById('preview-mapa-box');
            if (col && mapa) { mapa.style.height = col.offsetHeight + 'px'; }
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

          window.definirEstetica = async function() {
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
                    if (window.__esteticaHook) { window.__esteticaHook.pushEvent('imagen_actualizada', {}); }
                  }
                  else alert('Error al subir la imagen');
                });
            }, 'image/png');
          };

          window.intentarVolverEstetica = function(event) {
            event.preventDefault();
            if (esteticaModificado) {
              document.getElementById('aviso-salir-estetica').style.display = 'flex';
            } else {
              window.__esteticaHook.pushEvent('volver_mi_tienda', {});
            }
          }

          window.guardarYSalirEstetica = async function() {
            document.getElementById('aviso-salir-estetica').style.display = 'none';
            await definirEstetica();
            window.__esteticaHook.pushEvent('volver_mi_tienda', {});
          }

          window.salirSinGuardarEstetica = function() {
            document.getElementById('aviso-salir-estetica').style.display = 'none';
            window.__esteticaHook.pushEvent('volver_mi_tienda', {});
          }
        },
        destroyed() {
          if (window.__esteticaHook === this) { window.__esteticaHook = null; }
          window.actualizarPreviewColor = undefined;
          window.aplicarPaletaRapida = undefined;
          window.definirEstetica = undefined;
          window.abrirCropperFromInput = undefined;
          window.dale_cerrarCropper = undefined;
          window.dale_confirmarCrop = undefined;
          window.intentarVolverEstetica = undefined;
          window.guardarYSalirEstetica = undefined;
          window.salirSinGuardarEstetica = undefined;
        }
      }
    </script>
    """
  end
end

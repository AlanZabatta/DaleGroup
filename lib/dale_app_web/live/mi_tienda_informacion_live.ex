defmodule DaleAppWeb.MiTiendaInformacionLive do
  use DaleAppWeb, :live_view

  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Brands.BrandLocation

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    {:ok, assign(socket, brand: brand)}
  end

  def handle_event("volver_mi_tienda", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/mi-tienda")}
  end

  def handle_event("guardar_gestion", %{"brand" => brand_params}, socket) do
    brand = socket.assigns.brand

    brand_params =
      case Map.get(brand_params, "categorias") do
        nil -> Map.put(brand_params, "categorias", [])
        "" -> Map.put(brand_params, "categorias", [])
        cats when is_binary(cats) ->
          lista = cats |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
          Map.put(brand_params, "categorias", lista)
        _ -> brand_params
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
        _ -> brand_params
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
        _ -> :ok
      end
    end)

    {:noreply,
     socket
     |> assign(brand: brand_actualizada)
     |> push_navigate(to: ~p"/mi-tienda")}
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
        <p style="font-size:14px; color:#555; margin:0 0 22px; line-height:1.5; font-family:Poppins,sans-serif;">Elegí una dirección de la lista de sugerencias, no la escribas libremente.</p>
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
          <button onclick="if(window.__accionSiGestion) window.__accionSiGestion();" style="flex:1; background:#186904; color:#fff; border:none; border-radius:14px; padding:13px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">Sí</button>
          <button onclick="document.getElementById('aviso-confirmar-vacios').style.display='none'" style="flex:1; background:#fff; color:#186904; border:2px solid #186904; border-radius:14px; padding:11px 0; font-size:14px; font-weight:600; font-family:Poppins,sans-serif; cursor:pointer;">No</button>
        </div>
      </div>
    </div>

    <div id="mi-tienda-informacion-root" phx-hook=".InformacionHook" style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <a href="#" onclick="intentarVolverInformacion(event)" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Gestionar información</p>
      <%= if @brand do %>
        <form id="form-gestion" onsubmit="return validarAntesDeGuardar(event)">
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Nombre de la tienda</p>
            <input type="text" name="brand[name]" id="input-nombre-tienda" value={@brand.name} oninput="gestionModificado = true" style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; color: #333; outline: none; box-sizing: border-box; background: white;"/>
          </div>
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Direcciones</p>
            <div id="direcciones-container" phx-update="ignore"></div>
            <button type="button" onclick="agregarDireccion()" style="margin-top: 8px; background: white; border: 1.5px dashed #cfe4cf; border-radius: 16px; padding: 10px 16px; cursor: pointer; color: #186904; font-size: 13px; font-weight: 600; font-family: Poppins, sans-serif;">+ Agregar dirección</button>
            <input type="hidden" name="brand[address]" id="address-hidden" value={@brand.address}/>
            <input type="hidden" name="brand[address_full]" id="address-full-hidden" value={@brand.address_full}/>
          </div>
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Modalidad</p>
            <select name="brand[modalidad]" id="select-modalidad-tienda" onchange="gestionModificado = true" style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; color: #333; outline: none; box-sizing: border-box; background: white;">
              <option value="presencial" selected={@brand.modalidad == "presencial"}>Presencial</option>
              <option value="digital" selected={@brand.modalidad == "digital"}>Solo Digital</option>
              <option value="ambos" selected={@brand.modalidad == "ambos"}>Presencial y Digital</option>
            </select>
          </div>
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Horario de atención</p>
            <input type="text" name="brand[horario_atencion]" id="input-horario-tienda" value={@brand.horario_atencion} placeholder="Ej: Lun a Sáb 10 a 20hs" oninput="gestionModificado = true"
              style="width: 100%; padding: 13px 16px; border: 1.5px solid #cfe4cf; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; color: #333; outline: none; box-sizing: border-box; background: white;"/>
          </div>
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Margen sobre venta online</p>
            <p style="font-size: 12.5px; color: #555; margin: 0 0 10px; font-family: Poppins, sans-serif; line-height: 1.6;">
              Dale cobra un máximo de 8% de comisión por venta online. Elegí cuánto de ese margen querés trasladarle al cliente sobre tu precio de local — el resto queda como tu ganancia extra por vender online. Con 0%, el cliente paga exactamente lo mismo que en tu local.
            </p>
            <p style="font-size: 12.5px; color: #186904; margin: 0 0 10px; font-family: Poppins, sans-serif; line-height: 1.6; background: #eef4ec; border-radius: 12px; padding: 10px 12px;">
              💡 Cuanto más margen asumas vos (en vez de trasladarlo al cliente) y más parejo esté tu precio online con el de tu local, tu marca recibe un pequeño impulso en el algoritmo de Dale para aparecerle a más usuarios.
            </p>
            <p style="font-size: 12px; color: #c0392b; margin: 0 0 12px; font-family: Poppins, sans-serif; line-height: 1.6; background: #fff3f2; border-radius: 12px; padding: 10px 12px;">
              ⚠️ Inflar artificialmente el precio de local para simular que estás asumiendo el margen (por ejemplo, subiendo un 8% por detrás en Stock y declarando acá 0%) viola los Términos de DaleGroup y da lugar a sanciones graves y permanentes sobre la cuenta de tu marca.
            </p>
            <div style="background: white; border-radius: 16px; padding: 18px 16px 14px; box-shadow: inset 0 1px 3px rgba(24,105,4,0.06);">
              <p id="margen-online-valor" style="font-size: 40px; font-weight: 800; color: #186904; text-align: center; margin: 0 0 4px; font-family: Poppins, sans-serif; line-height: 1;">{@brand.margen_online}%</p>
              <p id="margen-online-descripcion" style="font-size: 11.5px; color: #999; text-align: center; margin: 0 0 16px; font-family: Poppins, sans-serif;"></p>
              <input type="range" min="0" max="8" step="1" name="brand[margen_online]" id="input-margen-online" value={@brand.margen_online} oninput="actualizarMargenOnlineSlider(this)"
                style="width: 100%; height: 8px; border-radius: 8px; outline: none; cursor: pointer; accent-color: #186904; box-sizing: border-box;"/>
              <div style="display: flex; justify-content: space-between; margin-top: 6px;">
                <span style="font-size: 10.5px; color: #aaa; font-family: Poppins, sans-serif; font-weight: 600;">0% (mismo precio)</span>
                <span style="font-size: 10.5px; color: #aaa; font-family: Poppins, sans-serif; font-weight: 600;">8% (tope máximo)</span>
              </div>
            </div>
          </div>
          <div style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 16px;">
            <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 8px; text-transform: uppercase; letter-spacing: 0.6px;">Categorías</p>
            <p style="font-size: 12.5px; color: #888; margin: 0 0 12px; font-family: Poppins, sans-serif;">Seleccioná las que mejor describen tu marca.</p>
            <input type="hidden" name="brand[categorias]" id="categorias-hidden" value={Enum.join(@brand.categorias || [], ",")}/>
            <div style="display: flex; flex-wrap: wrap; gap: 8px;">
              <%= for cat <- ["Hombre", "Mujer", "Casual", "Elegante", "Street", "Sport", "Ropa", "Accesorios", "Calzado"] do %>
                <% activa = cat in (@brand.categorias || []) %>
                <button type="button"
                  data-cat={cat}
                  onclick="toggleCategoria(this)"
                  style={"padding: 9px 16px; border-radius: 20px; cursor: pointer; font-size: 13px; font-family: Poppins, sans-serif; font-weight: 600; transition: all 0.2s; border: 1.5px solid #{if activa, do: "#186904", else: "#cfe4cf"}; background: #{if activa, do: "#186904", else: "white"}; color: #{if activa, do: "white", else: "#666"};"}>
                  <%= cat %>
                </button>
              <% end %>
            </div>
          </div>
          <button type="submit" style="width: 100%; background-color: #186904; color: white; padding: 14px 0; border: none; border-radius: 16px; cursor: pointer; font-size: 15px; font-weight: 700; font-family: Poppins, sans-serif; margin-bottom: 22px; box-shadow: 0 4px 14px rgba(24,105,4,0.20);">
            Guardar cambios
          </button>
        </form>
      <% else %>
        <p style="font-family: Poppins, sans-serif; color: #666;">No tenés una tienda asignada todavía.</p>
      <% end %>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".InformacionHook">
      export default {
        mounted() {
          window.__informacionHook = this;
          let gestionModificado = false;

          window.actualizarVisualMargenOnlineSlider = (el) => {
            const valor = parseInt(el.value, 10) || 0;
            const elValor = document.getElementById('margen-online-valor');
            const elDescripcion = document.getElementById('margen-online-descripcion');
            if (elValor) elValor.textContent = valor + '%';
            const pct = (valor / 8) * 100;
            el.style.background = 'linear-gradient(to right, #186904 0%, #186904 ' + pct + '%, #e0e0e0 ' + pct + '%, #e0e0e0 100%)';
            if (elDescripcion) {
              if (valor === 0) {
                elDescripcion.textContent = 'No le trasladás nada al cliente — asumís vos todo el margen';
              } else if (valor === 8) {
                elDescripcion.textContent = 'Tope máximo — le trasladás todo el margen al cliente';
              } else {
                elDescripcion.textContent = 'Trasladás una parte al cliente, el resto es tu ganancia extra';
              }
            }
          };
          window.actualizarMargenOnlineSlider = (el) => {
            gestionModificado = true;
            window.actualizarVisualMargenOnlineSlider(el);
          };
          const sliderMargenInicial = document.getElementById('input-margen-online');
          if (sliderMargenInicial) window.actualizarVisualMargenOnlineSlider(sliderMargenInicial);

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

          const categoriasHiddenEl = document.getElementById('categorias-hidden');
          let seleccionadas = categoriasHiddenEl && categoriasHiddenEl.value ? categoriasHiddenEl.value.split(',').filter(c => c !== '') : [];

          window.toggleCategoria = function(btn) {
            gestionModificado = true;
            const cat = btn.getAttribute('data-cat');
            if (seleccionadas.includes(cat)) {
              seleccionadas = seleccionadas.filter(c => c !== cat);
              btn.style.background = 'white'; btn.style.color = '#666'; btn.style.borderColor = '#e0e0e0';
            } else {
              seleccionadas.push(cat);
              btn.style.background = '#186904'; btn.style.color = 'white'; btn.style.borderColor = '#186904';
            }
            categoriasHiddenEl.value = seleccionadas.join(',');
          }

          function direccionesInvalidas() {
            const inputs = document.querySelectorAll('#direcciones-container input[type="text"]');
            for (const input of inputs) {
              const valor = input.value.trim();
              if (valor !== '' && !input.dataset.corto && !input.dataset.original) { return true; }
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
              categorias: document.getElementById('categorias-hidden').value,
              margen_online: document.getElementById('input-margen-online').value
            };
          }

          function guardarGestion() {
            if (window.__informacionHook) {
              window.__informacionHook.pushEvent('guardar_gestion', { brand: recolectarDatosGestion() });
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
              window.__accionSiGestion = window.continuarGuardadoGestion;
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

          window.__valoresOriginalesGestion = {
            nombre: document.getElementById('input-nombre-tienda').value,
            horario: document.getElementById('input-horario-tienda').value,
            modalidad: document.getElementById('select-modalidad-tienda').value,
            categorias: document.getElementById('categorias-hidden').value,
            direcciones: document.getElementById('address-full-hidden').value,
            margen_online: document.getElementById('input-margen-online').value
          };
          window.calcularCambiosGestion = function() {
            const orig = window.__valoresOriginalesGestion;
            if (!orig) return [];
            const cambios = [];
            const nombreActual = document.getElementById('input-nombre-tienda').value;
            if (nombreActual !== orig.nombre) cambios.push('Nombre: de "' + orig.nombre + '" a "' + nombreActual + '"');
            const horarioActual = document.getElementById('input-horario-tienda').value;
            if (horarioActual !== orig.horario) cambios.push('Horario: de "' + orig.horario + '" a "' + horarioActual + '"');
            const modalidadActual = document.getElementById('select-modalidad-tienda').value;
            if (modalidadActual !== orig.modalidad) {
              const etiquetas = { presencial: 'Presencial', digital: 'Solo Digital', ambos: 'Presencial y Digital' };
              cambios.push('Modalidad: de "' + (etiquetas[orig.modalidad] || orig.modalidad) + '" a "' + (etiquetas[modalidadActual] || modalidadActual) + '"');
            }
            const categoriasActual = document.getElementById('categorias-hidden').value;
            if (categoriasActual !== orig.categorias) cambios.push('Categorias modificadas');
            const direccionesActual = document.getElementById('address-full-hidden').value;
            if (direccionesActual !== orig.direcciones) cambios.push('Direcciones modificadas');
            const margenActual = document.getElementById('input-margen-online').value;
            if (margenActual !== orig.margen_online) cambios.push('Margen online: de ' + orig.margen_online + '% a ' + margenActual + '%');
            return cambios;
          };
          window.intentarVolverInformacion = function(event) {
            event.preventDefault();
            const cambiosSalida = window.calcularCambiosGestion();
            if (cambiosSalida.length > 0) {
              document.getElementById('aviso-confirmar-vacios-texto').innerHTML = 'Tenes estos cambios sin guardar:<br><br>- ' + cambiosSalida.join('<br>- ') + '<br><br>Si salis ahora los vas a perder. ¿Estas seguro?';
              window.__accionSiGestion = function() {
                document.getElementById('aviso-confirmar-vacios').style.display = 'none';
                window.__informacionHook.pushEvent('volver_mi_tienda', {});
              };
              document.getElementById('aviso-confirmar-vacios').style.display = 'flex';
            } else {
              window.__informacionHook.pushEvent('volver_mi_tienda', {});
            }
          }
        },
        destroyed() {
          if (window.__informacionHook === this) { window.__informacionHook = null; }
          window.agregarDireccion = undefined;
          window.toggleCategoria = undefined;
          window.validarAntesDeGuardar = undefined;
          window.continuarGuardadoGestion = undefined;
          window.intentarVolverInformacion = undefined;
        }
      }
    </script>
    """
  end
end

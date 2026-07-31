defmodule DaleAppWeb.StockPanoramicoLive do
  use DaleAppWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Products.{Product, StockItem, CategoriaCustom}

  @categorias_fijas [
    %{codigo: "01", nombre: "Remeras", icono: "remera"},
    %{codigo: "02", nombre: "Pantalones", icono: "pantalon"},
    %{codigo: "03", nombre: "Buzos", icono: "buzo"},
    %{codigo: "04", nombre: "Camperas", icono: "campera"}
  ]

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil
    if brand, do: asegurar_categorias_fijas(brand.id)
    productos_todos = if brand, do: listar_productos_con_stock(brand.id), else: []
    categorias = if brand, do: listar_categorias(brand.id), else: []

    {:ok,
     assign(socket,
       brand: brand,
       productos_todos: productos_todos,
       productos: productos_todos,
       termino: "",
       categoria_seleccionada: nil,
       categorias: categorias,
       mostrar_modal_categoria: false,
       icono_elegido: nil,
       imagen_subida_url: nil,
       error_categoria: nil,
       editando_categoria_id: nil
     )}
  end

  defp asegurar_categorias_fijas(brand_id) do
    codigos_existentes =
      from(c in CategoriaCustom, where: c.brand_id == ^brand_id, select: c.codigo_tipo)
      |> Repo.all()
      |> MapSet.new()

    Enum.each(@categorias_fijas, fn cat ->
      unless MapSet.member?(codigos_existentes, cat.codigo) do
        %CategoriaCustom{}
        |> CategoriaCustom.changeset(%{nombre: cat.nombre, icono: cat.icono, codigo_tipo: cat.codigo, brand_id: brand_id})
        |> Repo.insert()
      end
    end)
  end

  def handle_event("buscar", %{"termino" => termino}, socket) do
    termino_norm = termino |> String.trim() |> String.downcase()

    productos =
      if termino_norm == "" do
        socket.assigns.productos_todos
      else
        Enum.filter(socket.assigns.productos_todos, fn {producto, _total, codigos} ->
          nombre_match = producto.name && String.contains?(String.downcase(producto.name), termino_norm)
          codigo_match = Enum.any?(codigos, fn c -> String.contains?(String.downcase(c), termino_norm) end)
          nombre_match || codigo_match
        end)
      end

    {:noreply, assign(socket, productos: productos, termino: termino)}
  end

  def handle_event("elegir_categoria", %{"tipo" => tipo, "nombre" => nombre}, socket) do
    {:noreply, assign(socket, categoria_seleccionada: %{codigo: tipo, nombre: nombre})}
  end

  def handle_event("volver_categorias", _params, socket) do
    {:noreply, assign(socket, categoria_seleccionada: nil)}
  end

  def handle_event("abrir_modal_categoria", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_categoria: true, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil, editando_categoria_id: nil)}
  end

  def handle_event("abrir_modal_editar", %{"id" => id}, socket) do
    cat = Enum.find(socket.assigns.categorias, fn c -> to_string(c.id) == id end)

    if cat do
      {:noreply,
       assign(socket,
         mostrar_modal_categoria: true,
         editando_categoria_id: cat.id,
         icono_elegido: cat.icono,
         imagen_subida_url: cat.imagen_url,
         error_categoria: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cerrar_modal_categoria", _params, socket) do
    {:noreply, assign(socket, mostrar_modal_categoria: false)}
  end

  def handle_event("elegir_icono", %{"icono" => icono}, socket) do
    {:noreply, assign(socket, icono_elegido: icono, imagen_subida_url: nil)}
  end

  def handle_event("guardar_categoria", %{"nombre" => nombre}, socket) do
    nombre = String.trim(nombre)
    icono = socket.assigns.icono_elegido
    imagen_url = socket.assigns.imagen_subida_url
    editando_id = socket.assigns.editando_categoria_id

    cond do
      nombre == "" ->
        {:noreply, assign(socket, error_categoria: "Ponele un nombre a la categoría.")}

      is_nil(icono) && is_nil(imagen_url) ->
        {:noreply, assign(socket, error_categoria: "Elegí un ícono o subí una imagen.")}

      editando_id ->
        cat = Repo.get(CategoriaCustom, editando_id)

        case cat |> CategoriaCustom.changeset(%{nombre: nombre, icono: icono, imagen_url: imagen_url}) |> Repo.update() do
          {:ok, _} ->
            categorias = listar_categorias(socket.assigns.brand.id)
            {:noreply, assign(socket, categorias: categorias, mostrar_modal_categoria: false, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil, editando_categoria_id: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error_categoria: "No se pudo guardar.")}
        end

      true ->
        codigo_tipo = proximo_codigo_tipo(socket.assigns.brand.id)

        case %CategoriaCustom{}
             |> CategoriaCustom.changeset(%{nombre: nombre, icono: icono, imagen_url: imagen_url, codigo_tipo: codigo_tipo, brand_id: socket.assigns.brand.id})
             |> Repo.insert() do
          {:ok, _cat} ->
            categorias = listar_categorias(socket.assigns.brand.id)
            {:noreply, assign(socket, categorias: categorias, mostrar_modal_categoria: false, icono_elegido: nil, imagen_subida_url: nil, error_categoria: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error_categoria: "No se pudo crear la categoría.")}
        end
    end
  end

  defp proximo_codigo_tipo(brand_id) do
    usados_fijos = Enum.map(@categorias_fijas, & &1.codigo)

    usados_custom =
      from(c in CategoriaCustom, where: c.brand_id == ^brand_id, select: c.codigo_tipo)
      |> Repo.all()

    usados = MapSet.new(usados_fijos ++ usados_custom)

    Enum.find(5..99, fn n -> not MapSet.member?(usados, String.pad_leading(Integer.to_string(n), 2, "0")) end)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp listar_categorias(brand_id) do
    from(c in CategoriaCustom, where: c.brand_id == ^brand_id, order_by: [asc: c.codigo_tipo])
    |> Repo.all()
  end

  defp listar_productos_con_stock(brand_id) do
    variantes_por_producto =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        select: {s.product_id, s.codigo}
      )
      |> Repo.all()
      |> Enum.group_by(fn {product_id, _codigo} -> product_id end, fn {_product_id, codigo} -> codigo end)

    totales =
      from(s in StockItem,
        join: p in Product, on: p.id == s.product_id,
        where: p.brand_id == ^brand_id,
        group_by: s.product_id,
        select: {s.product_id, sum(s.cantidad)}
      )
      |> Repo.all()
      |> Map.new()

    from(p in Product, where: p.brand_id == ^brand_id, order_by: [asc: p.name])
    |> Repo.all()
    |> Enum.map(fn producto ->
      total = Map.get(totales, producto.id, 0)
      codigos_variantes = Map.get(variantes_por_producto, producto.id, [])
      codigo_base = if producto.codigo_tipo && producto.codigo_numero, do: [producto.codigo_tipo <> producto.codigo_numero], else: []
      {producto, total, codigos_variantes ++ codigo_base}
    end)
  end

  defp icono_svg("remera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/>)
  defp icono_svg("pantalon"), do: ~s(<path d="M6 3h12l1 6-2 12h-4l-1-9-1 9h-4l-2-12z"/>)
  defp icono_svg("buzo"), do: ~s(<path d="M15 4l6 3v5h-3v9a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-9h-3v-5l6 -3a3 3 0 0 0 6 0"/>)
  defp icono_svg("campera"), do: ~s(<path d="M15 4l6 2v5h-3v8a1 1 0 0 1 -1 1h-10a1 1 0 0 1 -1 -1v-8h-3v-5l6 -2a3 3 0 0 0 6 0"/><path d="M9 7l3 3l3 -3"/><line x1="12" y1="10" x2="12" y2="20"/>)
  defp icono_svg("anteojos"), do: ~s(<circle cx="6.5" cy="12" r="3.5"/><circle cx="17.5" cy="12" r="3.5"/><line x1="10" y1="11" x2="14" y2="11"/><path d="M3 11l-1 1"/><path d="M21 11l1 1"/>)
  defp icono_svg("bolso"), do: ~s(<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M8 8v-2a4 4 0 0 1 8 0v2"/>)
  defp icono_svg(_), do: ~s(<circle cx="12" cy="12" r="8"/>)

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh; position: relative;">
      <%= if @categoria_seleccionada do %>
        <button type="button" phx-click="volver_categorias" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; padding: 0; margin-bottom: 16px;">&#x2715;</button>
      <% else %>
        <a href="/mi-tienda" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>
      <% end %>

      <%= if @categoria_seleccionada do %>
        <p style="font-size: 26px; font-weight: 800; margin: 0 0 20px;">
          <span style="color: #aaa; cursor: pointer;" phx-click="volver_categorias">Mi Stock</span>
          <span style="color: #aaa;">/</span>
          <span style="color: #186904;"><%= @categoria_seleccionada.nombre %></span>
        </p>
      <% else %>
        <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Mi Stock</p>
      <% end %>

      <style>
        @keyframes blurCambioBusqueda {
          0% { filter: blur(0px); opacity: 1; }
          45% { filter: blur(6px); opacity: 0.2; }
          55% { filter: blur(6px); opacity: 0.2; }
          100% { filter: blur(0px); opacity: 1; }
        }
        .busqueda-animada { animation: blurCambioBusqueda 0.6s ease; }
      </style>

      <form phx-change="buscar" phx-submit="buscar" id="form-buscar-stock" phx-hook=".BuscadorStock" style="position: relative; width: 100%; margin-bottom: 20px;">
        <input
          type="text"
          name="termino"
          id="input-buscar-stock"
          value={@termino}
          autocomplete="off"
          style="width: 100%; box-sizing: border-box; padding: 13px 16px 13px 42px; border: 1.5px solid #999; border-radius: 16px; font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #333; outline: none; background: white;"
        />
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="position: absolute; left: 14px; top: 50%; transform: translateY(-50%); pointer-events: none;"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <span id="placeholder-buscar-stock" style="position: absolute; left: 42px; top: 50%; transform: translateY(-50%); font-family: Poppins, sans-serif; font-size: 14px; font-weight: 700; color: #186904; pointer-events: none;">Buscar Mi Stock</span>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".BuscadorStock">
          export default {
            mounted() {
              this.iniciar();
            },
            updated() {
              this.iniciar();
            },
            iniciar() {
              if (this._yaIniciado) return;
              this._yaIniciado = true;

              const palabras = ["Buscar Mi Stock", "Remera", "030105218", "Pantalon", "Buzo", "070311046", "Campera", "Zapatilla", "010200432"];
              let idx = 0;
              const input = document.getElementById('input-buscar-stock');
              const label = document.getElementById('placeholder-buscar-stock');

              const actualizarVisibilidad = () => {
                if (input && label) {
                  label.style.display = (document.activeElement === input || input.value !== "") ? "none" : "block";
                }
              };

              if (input) {
                input.addEventListener('focus', actualizarVisibilidad);
                input.addEventListener('blur', actualizarVisibilidad);
                input.addEventListener('input', actualizarVisibilidad);
              }

              this._intervalo = setInterval(() => {
                idx = (idx + 1) % palabras.length;
                const labelActual = document.getElementById('placeholder-buscar-stock');
                if (labelActual && document.activeElement !== input) {
                  labelActual.classList.remove('busqueda-animada'); void labelActual.offsetWidth; labelActual.classList.add('busqueda-animada');
                  setTimeout(() => { labelActual.textContent = palabras[idx]; }, 270);
                }
              }, 3000);
            },
            destroyed() {
              if (this._intervalo) clearInterval(this._intervalo);
            }
          }
        </script>
      </form>

      <%= if is_nil(@categoria_seleccionada) do %>
        <p style="font-size: 12px; font-weight: 700; color: #186904; margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px;">Categorías</p>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px;">
          <%= for cat <- @categorias do %>
            <div style="position: relative; border-radius: 22px; overflow: hidden; border: 1.5px solid #eef0ea; box-shadow: 0 6px 18px rgba(24,105,4,0.10); background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%);">
              <button type="button" phx-click="abrir_modal_editar" phx-value-id={cat.id} style="position: absolute; top: 8px; left: 8px; z-index: 5; width: 26px; height: 26px; border-radius: 50%; background: white; border: 1px solid #eee; cursor: pointer; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(0,0,0,0.08);">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              </button>

              <button type="button" phx-click="elegir_categoria" phx-value-tipo={cat.codigo_tipo} phx-value-nombre={cat.nombre} style="width: 100%; background: none; border: none; cursor: pointer; padding: 0; text-align: left;">
                <div style="aspect-ratio: 3/4; display: flex; align-items: center; justify-content: center; overflow: hidden;">
                  <%= if cat.imagen_url do %>
                    <img src={cat.imagen_url} style="width: 100%; height: 100%; object-fit: cover;" />
                  <% else %>
                    <svg width="55%" height="55%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                      {raw(icono_svg(cat.icono))}
                    </svg>
                  <% end %>
                </div>
                <div style="padding: 10px 14px 14px;">
                  <p style="font-size: 14px; font-weight: 700; margin: 0; color: #111;"><%= cat.nombre %></p>
                </div>
              </button>
            </div>
          <% end %>

          <button type="button" phx-click="abrir_modal_categoria" style="border-radius: 22px; overflow: hidden; border: 1.5px dashed #d8dcd2; background: #fbfbf9; display: flex; flex-direction: column; cursor: pointer; padding: 0;">
            <div style="aspect-ratio: 3/4; display: flex; align-items: center; justify-content: center;">
              <span style="font-size: 40px; color: #bbb; font-weight: 300; line-height: 1;">+</span>
            </div>
            <div style="padding: 10px 14px 14px;">
              <p style="font-size: 14px; font-weight: 700; margin: 0; color: transparent; user-select: none;">.</p>
            </div>
          </button>
        </div>
      <% end %>

      <%= if @mostrar_modal_categoria do %>
        <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.45); z-index: 9999; display: flex; align-items: center; justify-content: center;">
          <div style="background: #fff; border-radius: 24px; width: 320px; max-width: 88%; padding: 24px 20px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); max-height: 88vh; overflow-y: auto;">
            <p style="font-size: 18px; font-weight: 700; color: #186904; margin: 0 0 6px; text-align: center;">
              <%= if @editando_categoria_id, do: "Editar categoría", else: "Nueva categoría" %>
            </p>

            <div id="preview-imagen-categoria" style="width: 100%; aspect-ratio: 3/4; max-height: 130px; border-radius: 18px; border: 1.5px solid #eef0ea; background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); display: flex; align-items: center; justify-content: center; margin: 14px 0; overflow: hidden;">
              <%= cond do %>
                <% @imagen_subida_url -> %>
                  <img src={@imagen_subida_url} style="width: 100%; height: 100%; object-fit: cover;" />
                <% @icono_elegido -> %>
                  <svg width="35%" height="35%" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    {raw(icono_svg(@icono_elegido))}
                  </svg>
                <% true -> %>
                  <span style="font-size: 12px; color: #bbb; font-family: Poppins, sans-serif;">Elegí un ícono o subí una foto</span>
              <% end %>
            </div>

            <label for="input-imagen-categoria" style="display: block; width: 100%; box-sizing: border-box; text-align: center; background: white; color: #186904; border: 1.5px solid #186904; border-radius: 14px; padding: 10px; font-family: Poppins, sans-serif; font-size: 13px; font-weight: 700; cursor: pointer; margin-bottom: 14px;">
              Subir foto de mi galería
            </label>
            <input type="file" id="input-imagen-categoria" accept="image/*" style="display: none;" phx-hook=".SubidaImagenCategoria" data-categoria-id={@editando_categoria_id} />
            <script :type={Phoenix.LiveView.ColocatedHook} name=".SubidaImagenCategoria">
              export default {
                mounted() {
                  this.el.addEventListener('change', async (e) => {
                    const file = e.target.files[0];
                    if (!file) return;
                    const catId = this.el.dataset.categoriaId;
                    if (!catId) {
                      alert('Primero creá la categoría con un ícono, y después editala para subir la foto.');
                      return;
                    }
                    const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
                    const formData = new FormData();
                    formData.append('_csrf_token', csrfToken);
                    formData.append('imagen', file, file.name);
                    const res = await fetch('/mi-tienda/categorias/' + catId + '/imagen', { method: 'POST', body: formData });
                    const data = await res.json();
                    if (data.ok) {
                      const preview = document.getElementById('preview-imagen-categoria');
                      if (preview) preview.innerHTML = '<img src="' + data.url + '" style="width:100%; height:100%; object-fit:cover;" />';
                    }
                  });
                }
              }
            </script>

            <p style="font-size: 11px; color: #999; text-align: center; margin: 0 0 10px; font-family: Poppins, sans-serif;">o elegí un ícono</p>

            <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 16px;">
              <%= for icono <- ["remera", "pantalon", "buzo", "campera", "anteojos", "bolso"] do %>
                <button type="button" phx-click="elegir_icono" phx-value-icono={icono} style={"padding: 10px; border-radius: 12px; border: 1.5px solid #{if @icono_elegido == icono, do: "#186904", else: "#e0e0e0"}; background: #{if @icono_elegido == icono, do: "rgba(24,105,4,0.06)", else: "white"}; cursor: pointer; display: flex; align-items: center; justify-content: center;"}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#186904" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                    {raw(icono_svg(icono))}
                  </svg>
                </button>
              <% end %>
            </div>

            <form phx-submit="guardar_categoria">
              <input type="text" name="nombre" placeholder="Nombre de la categoría" autocomplete="off" value={if cat = Enum.find(@categorias, fn c -> c.id == @editando_categoria_id end), do: cat.nombre, else: ""} style="width: 100%; box-sizing: border-box; padding: 12px 14px; border: 1.5px solid #e0e0e0; border-radius: 14px; font-family: Poppins, sans-serif; font-size: 14px; outline: none; margin-bottom: 12px;" />

              <%= if @error_categoria do %>
                <p style="color: #c0392b; font-size: 12px; margin: 0 0 10px; font-family: Poppins, sans-serif;"><%= @error_categoria %></p>
              <% end %>

              <button type="submit" style="width: 100%; background: #186904; color: white; border: none; border-radius: 14px; padding: 12px 0; font-size: 14px; font-weight: 700; font-family: Poppins, sans-serif; cursor: pointer;">
                <%= if @editando_categoria_id, do: "Guardar cambios", else: "Crear categoría" %>
              </button>
            </form>
            <button type="button" phx-click="cerrar_modal_categoria" style="width: 100%; margin-top: 8px; background: none; color: #999; border: none; padding: 8px 0; font-size: 13px; font-family: Poppins, sans-serif; cursor: pointer;">Cancelar</button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

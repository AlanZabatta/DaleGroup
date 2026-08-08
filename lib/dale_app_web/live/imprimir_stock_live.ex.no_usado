defmodule DaleAppWeb.ImprimirStockLive do
  use DaleAppWeb, :live_view
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil

    {:ok, assign(socket, brand: brand, ruta_actual: "/mi-tienda/stock/imprimir")}
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 90px 18px 120px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; position: relative; z-index: 1;">
      <a href="/mi-tienda/stock" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</a>

      <p style="font-size: 22px; font-weight: 800; color: #186904; margin: 0 0 4px;">Imprimir códigos</p>
      <p style="font-size: 13px; color: #999; margin: 0 0 24px;">Elegí qué productos imprimir y en qué tamaño</p>

      <div id="selector-tamano-imprimir" phx-hook=".SelectorTamanoImprimir" style="background: linear-gradient(160deg, #ffffff 0%, #f6faf3 100%); border: 1.5px solid #d9ead9; border-radius: 18px; padding: 18px; box-shadow: 0 4px 14px rgba(24,105,4,0.10); margin-bottom: 20px;">
        <p style="font-size: 12.5px; font-weight: 700; color: #186904; margin: 0 0 14px;">Tamaño</p>

        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 20px;">
          <button type="button" data-tamano="chico" data-ancho-mm="25" data-alto-mm="30" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
            <span style="width: 14px; height: 14px; border-radius: 4px; background: #186904;"></span>
            <span style="font-size: 13px; font-weight: 700; color: #186904;">Chico</span>
            <span style="font-size: 10px; color: #999;">25×30mm</span>
          </button>

          <button type="button" data-tamano="mediano" data-ancho-mm="40" data-alto-mm="45" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
            <span style="width: 22px; height: 22px; border-radius: 5px; background: #186904;"></span>
            <span style="font-size: 13px; font-weight: 700; color: #186904;">Mediano</span>
            <span style="font-size: 10px; color: #999;">40×45mm</span>
          </button>

          <button type="button" data-tamano="grande" data-ancho-mm="60" data-alto-mm="70" onclick="elegirTamanoImprimir(this)" class="tarjeta-tamano-imprimir" style="display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 8px; border-radius: 16px; border: 1.5px solid #cfe4cf; background: white; cursor: pointer; font-family: Poppins, sans-serif;">
            <span style="width: 30px; height: 30px; border-radius: 6px; background: #186904;"></span>
            <span style="font-size: 13px; font-weight: 700; color: #186904;">Grande</span>
            <span style="font-size: 10px; color: #999;">60×70mm</span>
          </button>
        </div>

        <p id="texto-cantidad-hoja-imprimir" style="font-size: 11.5px; color: #666; text-align: center; margin: 0 0 10px;">Elegí un tamaño para ver la vista previa</p>

        <div style="display: flex; justify-content: center;">
          <div id="hoja-preview-imprimir" style="position: relative; width: 100%; max-width: 260px; aspect-ratio: 210 / 297; background: white; border: 1.5px solid #ddd; border-radius: 4px; box-shadow: 0 2px 10px rgba(0,0,0,0.08);"></div>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".SelectorTamanoImprimir">
          export default {
            mounted() {
              const ANCHO_HOJA_MM = 210;
              const ALTO_HOJA_MM = 297;
              const MARGEN_MM = 10;

              window.elegirTamanoImprimir = (btn) => {
                document.querySelectorAll('.tarjeta-tamano-imprimir').forEach(b => {
                  b.style.borderColor = '#cfe4cf';
                  b.style.background = 'white';
                });
                btn.style.borderColor = '#186904';
                btn.style.background = '#e6f4e6';

                const anchoMm = parseFloat(btn.dataset.anchoMm);
                const altoMm = parseFloat(btn.dataset.altoMm);

                const areaAnchoMm = ANCHO_HOJA_MM - (MARGEN_MM * 2);
                const areaAltoMm = ALTO_HOJA_MM - (MARGEN_MM * 2);

                const cols = Math.floor(areaAnchoMm / anchoMm);
                const rows = Math.floor(areaAltoMm / altoMm);
                const total = cols * rows;

                const texto = document.getElementById('texto-cantidad-hoja-imprimir');
                if (texto) texto.textContent = 'Entran ' + total + ' etiquetas por hoja (' + cols + ' columnas × ' + rows + ' filas)';

                const hoja = document.getElementById('hoja-preview-imprimir');
                if (!hoja) return;

                const escala = hoja.clientWidth / ANCHO_HOJA_MM;
                const margenPx = MARGEN_MM * escala;
                const anchoCeldaPx = anchoMm * escala;
                const altoCeldaPx = altoMm * escala;

                let html = '';
                for (let f = 0; f < rows; f++) {
                  for (let c = 0; c < cols; c++) {
                    const left = margenPx + (c * anchoCeldaPx);
                    const top = margenPx + (f * altoCeldaPx);
                    html += '<div style="position: absolute; left: ' + left + 'px; top: ' + top + 'px; width: ' + (anchoCeldaPx - 2) + 'px; height: ' + (altoCeldaPx - 2) + 'px; background: #186904; opacity: 0.75; border-radius: 2px;"></div>';
                  }
                }
                hoja.innerHTML = html;
              };

              const primero = document.querySelector('.tarjeta-tamano-imprimir[data-tamano="chico"]');
              if (primero) elegirTamanoImprimir(primero);
            }
          }
        </script>
      </div>

      <div style="border: 1.5px dashed #d9ead9; border-radius: 18px; padding: 40px 20px; text-align: center;">
        <p style="font-size: 13px; color: #bbb; margin: 0;">Acá va a ir el selector de productos y cantidades.</p>
      </div>
    </div>
    """
  end
end

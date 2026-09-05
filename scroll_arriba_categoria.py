ruta = 'lib/dale_app_web/live/stock_panoramico_live.ex'
with open(ruta, 'r', encoding='utf-8') as f:
    contenido = f.read()

viejo = '''  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh; position: relative;">'''

nuevo = '''  def render(assigns) do
    ~H"""
    <div id="stock-panoramico-wrapper" phx-hook=".ScrollArribaStock" data-categoria={@categoria_seleccionada && @categoria_seleccionada.codigo} style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh; position: relative;">
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollArribaStock">
        export default {
          mounted() {
            this._categoriaPrevia = this.el.dataset.categoria || "";
          },
          updated() {
            const categoriaActual = this.el.dataset.categoria || "";
            if (categoriaActual !== this._categoriaPrevia) {
              window.scrollTo(0, 0);
            }
            this._categoriaPrevia = categoriaActual;
          }
        }
      </script>'''

if viejo not in contenido:
    print("ERROR: no encontré el bloque esperado")
else:
    contenido = contenido.replace(viejo, nuevo)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(contenido)
    print("listo")

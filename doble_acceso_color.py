# --- Cambio 1: links en marcas_show_live.ex, agregar ?origen=marca ---
ruta1 = 'lib/dale_app_web/live/marcas_show_live.ex'
with open(ruta1, 'r', encoding='utf-8') as f:
    contenido1 = f.read()

viejo1 = '<a href={"/productos/#{producto.id}"} style="display: block; width: 100%; height: 100%;">'
nuevo1 = '<a href={"/productos/#{producto.id}?origen=marca"} style="display: block; width: 100%; height: 100%;">'

cuenta1 = contenido1.count(viejo1)
if cuenta1 == 0:
    print("ERROR 1: no encontré el link esperado en marcas_show_live.ex")
else:
    contenido1 = contenido1.replace(viejo1, nuevo1)
    with open(ruta1, 'w', encoding='utf-8') as f:
        f.write(contenido1)
    print(f"listo 1 ({cuenta1} reemplazos)")

# --- Cambio 2: producto_controller.ex, leer el parámetro "origen" ---
ruta2 = 'lib/dale_app_web/controllers/producto_controller.ex'
with open(ruta2, 'r', encoding='utf-8') as f:
    contenido2 = f.read()

viejo2 = '''  def mostrar(conn, %{"id" => id}) do
    product = Products.get_product(id)'''
nuevo2 = '''  def mostrar(conn, %{"id" => id} = params) do
    origen_marca = params["origen"] == "marca"
    product = Products.get_product(id)'''

viejo2b = '''      oferta: oferta,
      colores: colores
    )
  end'''
nuevo2b = '''      oferta: oferta,
      colores: colores,
      origen_marca: origen_marca
    )
  end'''

if viejo2 not in contenido2:
    print("ERROR 2a: no encontré el inicio de mostrar/2")
elif viejo2b not in contenido2:
    print("ERROR 2b: no encontré el final del render")
else:
    contenido2 = contenido2.replace(viejo2, nuevo2)
    contenido2 = contenido2.replace(viejo2b, nuevo2b)
    with open(ruta2, 'w', encoding='utf-8') as f:
        f.write(contenido2)
    print("listo 2")

# --- Cambio 3: mostrar.html.heex, decidir el color según origen_marca ---
ruta3 = 'lib/dale_app_web/controllers/producto_html/mostrar.html.heex'
with open(ruta3, 'r', encoding='utf-8') as f:
    contenido3 = f.read()

viejo3 = '''<% color_principal = "#186904" %>
<% color_letras = "#1a1a1a" %>
<% color_gestion = "#ffffff" %>'''

nuevo3 = '''<% color_principal = if @origen_marca, do: (@brand.colores && @brand.colores["principal"]) || "#186904", else: "#186904" %>
<% color_letras = if @origen_marca, do: (@brand.colores && @brand.colores["letras"]) || "#1a1a1a", else: "#1a1a1a" %>
<% color_gestion = if @origen_marca, do: (@brand.colores && @brand.colores["gestion"]) || "#ffffff", else: "#ffffff" %>'''

if viejo3 not in contenido3:
    print("ERROR 3: no encontré el bloque de colores en mostrar.html.heex")
else:
    contenido3 = contenido3.replace(viejo3, nuevo3)
    with open(ruta3, 'w', encoding='utf-8') as f:
        f.write(contenido3)
    print("listo 3")

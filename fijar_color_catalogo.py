ruta = 'lib/dale_app_web/controllers/producto_html/mostrar.html.heex'

with open(ruta, 'r', encoding='utf-8') as f:
    contenido = f.read()

viejo = '''<% color_principal = (@brand.colores && @brand.colores["principal"]) || "#186904" %>
<% color_letras = (@brand.colores && @brand.colores["letras"]) || "#1a1a1a" %>
<% color_gestion = (@brand.colores && @brand.colores["gestion"]) || "#ffffff" %>'''

nuevo = '''<% color_principal = "#186904" %>
<% color_letras = "#1a1a1a" %>
<% color_gestion = "#ffffff" %>'''

if viejo not in contenido:
    print("ERROR: no encontré el texto esperado, no se cambió nada")
else:
    contenido = contenido.replace(viejo, nuevo)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(contenido)
    print("listo")

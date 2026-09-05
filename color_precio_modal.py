# --- Cambio 1: backend, agregar color_principal al JSON de /productos/:id/detalle ---
ruta1 = 'lib/dale_app_web/controllers/producto_controller.ex'
with open(ruta1, 'r', encoding='utf-8') as f:
    contenido1 = f.read()

viejo1 = '''        brand_id: brand.id,
        brand_name: brand.name,
        favorito: favorito,'''

nuevo1 = '''        brand_id: brand.id,
        brand_name: brand.name,
        color_principal: (brand.colores && brand.colores["principal"]) || "#186904",
        favorito: favorito,'''

if viejo1 not in contenido1:
    print("ERROR 1: no encontré el texto esperado en producto_controller.ex")
else:
    contenido1 = contenido1.replace(viejo1, nuevo1)
    with open(ruta1, 'w', encoding='utf-8') as f:
        f.write(contenido1)
    print("listo 1")

# --- Cambio 2: JS del modal, pintar el precio con ese color ---
ruta2 = 'lib/dale_app_web/components/layouts/root.html.heex'
with open(ruta2, 'r', encoding='utf-8') as f:
    contenido2 = f.read()

viejo2 = """      document.getElementById('ps-precio-final').textContent = data.price ? ('$' + data.price) : '';"""

nuevo2 = """      document.getElementById('ps-precio-final').textContent = data.price ? ('$' + data.price) : '';
      document.getElementById('ps-precio-final').style.color = data.color_principal || '#186904';"""

if viejo2 not in contenido2:
    print("ERROR 2: no encontré el texto esperado en root.html.heex")
else:
    contenido2 = contenido2.replace(viejo2, nuevo2)
    with open(ruta2, 'w', encoding='utf-8') as f:
        f.write(contenido2)
    print("listo 2")

ruta = 'lib/dale_app_web/controllers/producto_controller.ex'
with open(ruta, 'r', encoding='utf-8') as f:
    contenido = f.read()

viejo = '''      brand_id: brand.id,
      brand_name: brand.name,
      favorito: favorito,'''

nuevo = '''      brand_id: brand.id,
      brand_name: brand.name,
      color_principal: (brand.colores && brand.colores["principal"]) || "#186904",
      favorito: favorito,'''

if viejo not in contenido:
    print("ERROR: sigue sin encontrarlo")
else:
    contenido = contenido.replace(viejo, nuevo)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(contenido)
    print("listo")

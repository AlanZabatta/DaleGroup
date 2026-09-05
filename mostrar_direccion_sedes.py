ruta = 'lib/dale_app_web/live/stock_panoramico_live.ex'
with open(ruta, 'r', encoding='utf-8') as f:
    contenido = f.read()

viejo = '''                  <label style="display: flex; align-items: center; gap: 10px; padding: 10px 12px; background: #f9f9f9; border-radius: 12px; cursor: pointer;">
                    <input type="checkbox" class="checkbox-sede-stock" value={sede.id} checked style="width: 18px; height: 18px; accent-color: #186904; cursor: pointer;" />
                    <span style="font-size: 13px; font-weight: 600; color: #333;"><%= sede.nombre %></span>
                  </label>'''

nuevo = '''                  <label style="display: flex; align-items: center; gap: 10px; padding: 10px 12px; background: #f9f9f9; border-radius: 12px; cursor: pointer;">
                    <input type="checkbox" class="checkbox-sede-stock" value={sede.id} checked style="width: 18px; height: 18px; accent-color: #186904; cursor: pointer;" />
                    <div style="display: flex; flex-direction: column;">
                      <span style="font-size: 13px; font-weight: 600; color: #333;"><%= sede.nombre %></span>
                      <span style="font-size: 11px; color: #999;"><%= if sede.direccion_completa && sede.direccion_completa != "", do: sede.direccion_completa, else: sede.address %></span>
                    </div>
                  </label>'''

if viejo not in contenido:
    print("ERROR: no encontré el bloque esperado")
else:
    contenido = contenido.replace(viejo, nuevo)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(contenido)
    print("listo")

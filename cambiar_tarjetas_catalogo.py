with open('lib/dale_app_web/controllers/page_html/productos.html.heex', 'r', encoding='utf-8') as f:
    lineas = f.readlines()

nuevo_bloque = '''  <div style="background: white; padding: 8px 16px 100px; display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
    <%= for %{producto: producto, marca: marca} <- @productos do %>
      <a href={"/productos/#{producto.id}"} style="text-decoration: none; display: flex; flex-direction: column; border-radius: 16px; overflow: hidden; box-shadow: 0 3px 12px rgba(0,0,0,0.06); background: white;">
        <div style="position: relative; overflow: hidden; background: #f5f5f5; aspect-ratio: 3/4;">
          <img src={producto.image} style="width: 100%; height: 100%; object-fit: cover; display: block;"/>
          <button
            onclick={"event.preventDefault(); event.stopPropagation(); toggleFavorito(this, #{producto.id})"}
            style="position: absolute; top: 8px; right: 8px; z-index: 10; background: white; border: none; border-radius: 50%; width: 28px; height: 28px; cursor: pointer; display: flex; align-items: center; justify-content: center; font-size: 14px; line-height: 1; box-shadow: 0 2px 6px rgba(0,0,0,0.2);">
            🤍
          </button>
        </div>
        <div style="background: white; padding: 8px 10px;">
          <p style="font-size: 12px; font-weight: 500; margin: 0; color: #111; font-family: 'Noto Sans', sans-serif;"><%= producto.name %></p>
          <%= if producto.original_price do %>
            <p style="font-size: 11px; color: #999; margin: 1px 0 0; text-decoration: line-through; font-family: 'Noto Sans', sans-serif;">$<%= producto.original_price %></p>
          <% end %>
          <%= if producto.price do %>
            <p style="font-size: 15px; font-weight: 700; color: #186904; margin: 0; font-family: 'Noto Sans', sans-serif;">$<%= producto.price %></p>
          <% end %>
          <p style="font-size: 11px; color: #888; margin: 2px 0 0; font-family: 'Noto Sans', sans-serif;"><%= marca.name %></p>
        </div>
      </a>
    <% end %>
  </div>
'''

lineas[31:55] = [nuevo_bloque]

with open('lib/dale_app_web/controllers/page_html/productos.html.heex', 'w', encoding='utf-8') as f:
    f.writelines(lineas)

print("listo")

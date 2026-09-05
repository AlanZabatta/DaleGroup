path = "lib/dale_app_web/components/layouts/root.html.heex"

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

start = 165  # línea 166 (índice 0)
end = 199    # hasta línea 199 inclusive

new_block = '''      <div id="bottom-bar" style="position: fixed; bottom: 0; left: 0; right: 0; z-index: 5000; background: rgba(255,255,255,0.96); backdrop-filter: blur(10px); border-top: 1px solid #f0f0f0; height: 11vh; display: flex; align-items: center; justify-content: space-around; padding: 0 8px; transition: none;">
        <div id="nav-bubble" style="position: absolute; top: 8px; height: calc(11vh - 16px); background: rgba(24, 105, 4, 0.12); border-radius: 18px; transition: transform 0.45s cubic-bezier(0.34, 1.56, 0.64, 1), width 0.45s cubic-bezier(0.34, 1.56, 0.64, 1); pointer-events: none; z-index: 0; opacity: 0;"></div>
        <% ruta = assigns[:ruta_actual] || (assigns[:conn] && @conn.request_path) || "" %>
        <a href="/amigos" class="nav-item" data-route="/amigos" data-active={to_string(ruta == "/amigos")} style={"position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; text-decoration: none; flex: 1; color: #{if ruta == "/amigos", do: "#186904", else: "#9a9a9a"};"}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 21a8 8 0 0 0-16 0"/><circle cx="10" cy="8" r="5"/><path d="M22 21a8 8 0 0 0-5.3-7.4"/><circle cx="19" cy="7" r="3" stroke-width="1.5"/>
          </svg>
          <span style={"font-size: 10px; font-family: 'Noto Sans', sans-serif; font-weight: #{if ruta == "/amigos", do: "600", else: "400"};"}>Amigos</span>
        </a>
        <a href="/perfil" class="nav-item" data-route="/perfil" data-active={to_string(ruta == "/perfil")} style={"position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; text-decoration: none; flex: 1; color: #{if ruta == "/perfil", do: "#186904", else: "#9a9a9a"};"}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 1 0-16 0"/>
          </svg>
          <span style={"font-size: 10px; font-family: 'Noto Sans', sans-serif; font-weight: #{if ruta == "/perfil", do: "600", else: "400"};"}>Perfil</span>
        </a>
        <a href="/" style="position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; text-decoration: none; flex: 1;">
          <img src="https://pub-04bf6639c7484e5c9c7f46651cfe8feb.r2.dev/7f63d78f-34ac-4f36-a9fa-68a4ff64c014.jpg" style="width: 58px; height: 58px; border-radius: 50%; object-fit: cover; box-shadow: 0 2px 8px rgba(0,0,0,0.15);"/>
        </a>
        <a href="/mapa" class="nav-item" data-route="/mapa" data-active={to_string(ruta == "/mapa")} style={"position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; text-decoration: none; flex: 1; color: #{if ruta == "/mapa", do: "#186904", else: "#9a9a9a"};"}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21"/><line x1="9" y1="3" x2="9" y2="18"/><line x1="15" y1="6" x2="15" y2="21"/>
          </svg>
          <span style={"font-size: 10px; font-family: 'Noto Sans', sans-serif; font-weight: #{if ruta == "/mapa", do: "600", else: "400"};"}>Mapa</span>
        </a>
        <a href="/mydream" class="nav-item" data-route="/mydream" data-active={to_string(ruta == "/mydream")} style={"position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; text-decoration: none; flex: 1; color: #{if ruta == "/mydream", do: "#186904", else: "#9a9a9a"};"}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>
            <line x1="12" y1="8" x2="12" y2="14"/><line x1="9" y1="11" x2="15" y2="11"/>
          </svg>
          <span style={"font-size: 10px; font-family: 'Noto Sans', sans-serif; font-weight: #{if ruta == "/mydream", do: "600", else: "400"};"}>Dream</span>
        </a>
      </div>
    </div>
    <script>
      let lastScroll = 0;
      function posicionarNavBubble(el, animar) {
        var bar = document.getElementById('bottom-bar');
        var bubble = document.getElementById('nav-bubble');
        if (!bar || !bubble || !el) return;
        var barRect = bar.getBoundingClientRect();
        var itemRect = el.getBoundingClientRect();
        var pad = 6;
        var left = itemRect.left - barRect.left + pad;
        var width = itemRect.width - pad * 2;
        if (!animar) { bubble.style.transition = 'none'; }
        bubble.style.opacity = '1';
        bubble.style.width = width + 'px';
        bubble.style.transform = 'translateX(' + left + 'px)';
        if (!animar) {
          bubble.offsetHeight;
          bubble.style.transition = '';
        }
      }
      function initNavBubble() {
        var activo = document.querySelector('.nav-item[data-active="true"]');
        if (activo) { posicionarNavBubble(activo, false); }
        document.querySelectorAll('.nav-item').forEach(function(item) {
          item.addEventListener('click', function() {
            posicionarNavBubble(item, true);
          });
        });
      }
      document.addEventListener('DOMContentLoaded', initNavBubble);
      window.addEventListener('resize', function() {
        var activo = document.querySelector('.nav-item[data-active="true"]');
        if (activo) { posicionarNavBubble(activo, false); }
      });
'''.split('\n')

new_lines = [l + '\n' for l in new_block]

lines[start:end] = new_lines

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)

print("Listo: barra de navegación reemplazada con nav-bubble líquida")

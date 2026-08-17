self.addEventListener('push', function(event) {
  var datos = {};
  try {
    datos = event.data ? event.data.json() : {};
  } catch (e) {
    datos = { titulo: 'Dale', cuerpo: event.data ? event.data.text() : '' };
  }

  var titulo = datos.titulo || 'Dale';
  var opciones = {
    body: datos.cuerpo || '',
    icon: '/favicon.ico',
    badge: '/favicon.ico',
    data: { url: datos.url || '/' }
  };

  event.waitUntil(self.registration.showNotification(titulo, opciones));
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(listaClientes) {
      for (var i = 0; i < listaClientes.length; i++) {
        var cliente = listaClientes[i];
        if (cliente.url.indexOf(url) !== -1 && 'focus' in cliente) {
          return cliente.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});

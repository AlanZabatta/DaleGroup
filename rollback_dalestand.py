ruta = 'lib/dale_app_web/live/stock_panoramico_live.ex'
with open(ruta, 'r', encoding='utf-8') as f:
    contenido = f.read()

viejo = """                  if (data.ok) {
                    if (imagenBlobStock && data.ids) {
                      const extension = imagenBlobStock.type && imagenBlobStock.type.includes('png') ? 'png'
                        : (imagenBlobStock.type && imagenBlobStock.type.includes('webp') ? 'webp' : 'jpg');
                      for (const id of data.ids) {
                        const imgForm = new FormData();
                        imgForm.append('_csrf_token', csrfTokenStock);
                        imgForm.append('imagen', imagenBlobStock, 'producto.' + extension);
                        await fetch('/mi-tienda/stock/productos/' + id + '/imagen', { method: 'POST', body: imgForm });
                      }
                    }

                    const erroresSubidaFotos = [];
                    if (data.colores_ids) {
                      for (const [cod, fotos] of Object.entries(imagenesPorColorStock)) {
                        const productId = data.colores_ids[cod];
                        if (!productId || !fotos) continue;
                        for (const foto of fotos) {
                          if (!foto || !foto.file) continue;
                          const ext = foto.file.type && foto.file.type.includes('png') ? 'png'
                            : (foto.file.type && foto.file.type.includes('webp') ? 'webp' : 'jpg');
                          const imgForm = new FormData();
                          imgForm.append('_csrf_token', csrfTokenStock);
                          imgForm.append('imagen', foto.file, 'producto.' + ext);
                          try {
                            const resImg = await fetch('/mi-tienda/stock/productos/' + productId + '/imagen', { method: 'POST', body: imgForm });
                            const dataImg = await resImg.json();
                            if (!dataImg.ok) {
                              erroresSubidaFotos.push('Color ' + cod + ': ' + (dataImg.error || 'error desconocido'));
                            }
                          } catch (e) {
                            erroresSubidaFotos.push('Color ' + cod + ': ' + e.message);
                          }
                        }
                      }
                    }
                    if (erroresSubidaFotos.length > 0) {
                      alert('El producto se guardó, pero algunas fotos no se pudieron subir:\\n\\n' + erroresSubidaFotos.join('\\n') + '\\n\\nVolvé a editar el producto para reintentar.');
                    }

                    window.location.href = '/mi-tienda/stock?categoria=' + codigoTipo;
                  } else {
                    btn.textContent = editandoArticuloActivo ? "Guardar cambios" : "Guardar producto"; btn.disabled = false;
                    alert('Error al guardar.');
                  }
                };"""

nuevo = """                  if (data.ok) {
                    const erroresSubidaFotos = [];

                    if (imagenBlobStock && data.ids) {
                      const extension = imagenBlobStock.type && imagenBlobStock.type.includes('png') ? 'png'
                        : (imagenBlobStock.type && imagenBlobStock.type.includes('webp') ? 'webp' : 'jpg');
                      for (const id of data.ids) {
                        const imgForm = new FormData();
                        imgForm.append('_csrf_token', csrfTokenStock);
                        imgForm.append('imagen', imagenBlobStock, 'producto.' + extension);
                        try {
                          const resImg = await fetch('/mi-tienda/stock/productos/' + id + '/imagen', { method: 'POST', body: imgForm });
                          const dataImg = await resImg.json();
                          if (!dataImg.ok) {
                            erroresSubidaFotos.push('Producto ' + id + ': ' + (dataImg.error || 'error desconocido'));
                          }
                        } catch (e) {
                          erroresSubidaFotos.push('Producto ' + id + ': ' + e.message);
                        }
                      }
                    }

                    if (data.colores_ids) {
                      for (const [cod, fotos] of Object.entries(imagenesPorColorStock)) {
                        const productId = data.colores_ids[cod];
                        if (!productId || !fotos) continue;
                        for (const foto of fotos) {
                          if (!foto || !foto.file) continue;
                          const ext = foto.file.type && foto.file.type.includes('png') ? 'png'
                            : (foto.file.type && foto.file.type.includes('webp') ? 'webp' : 'jpg');
                          const imgForm = new FormData();
                          imgForm.append('_csrf_token', csrfTokenStock);
                          imgForm.append('imagen', foto.file, 'producto.' + ext);
                          try {
                            const resImg = await fetch('/mi-tienda/stock/productos/' + productId + '/imagen', { method: 'POST', body: imgForm });
                            const dataImg = await resImg.json();
                            if (!dataImg.ok) {
                              erroresSubidaFotos.push('Color ' + cod + ': ' + (dataImg.error || 'error desconocido'));
                            }
                          } catch (e) {
                            erroresSubidaFotos.push('Color ' + cod + ': ' + e.message);
                          }
                        }
                      }
                    }

                    if (!editandoArticuloActivo && erroresSubidaFotos.length > 0 && codigoTipo === '99') {
                      const idsParaBorrar = data.ids && data.ids.length > 0 ? data.ids : (data.colores_ids ? Object.values(data.colores_ids) : []);
                      for (const idBorrar of idsParaBorrar) {
                        try {
                          await fetch('/mi-tienda/productos/' + idBorrar, {
                            method: 'DELETE',
                            headers: { 'x-csrf-token': csrfTokenStock }
                          });
                        } catch (e) {}
                      }
                      btn.textContent = "Guardar producto"; btn.disabled = false;
                      alert('No se pudo guardar el producto para DaleStand porque falló la subida de las fotos:\\n\\n' + erroresSubidaFotos.join('\\n') + '\\n\\nEl producto se eliminó, volvé a intentarlo.');
                      return;
                    }

                    if (erroresSubidaFotos.length > 0) {
                      alert('El producto se guardó, pero algunas fotos no se pudieron subir:\\n\\n' + erroresSubidaFotos.join('\\n') + '\\n\\nVolvé a editar el producto para reintentar.');
                    }

                    window.location.href = '/mi-tienda/stock?categoria=' + codigoTipo;
                  } else {
                    btn.textContent = editandoArticuloActivo ? "Guardar cambios" : "Guardar producto"; btn.disabled = false;
                    alert('Error al guardar.');
                  }
                };"""

if viejo not in contenido:
    print("ERROR: no encontré el bloque esperado")
else:
    contenido = contenido.replace(viejo, nuevo)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(contenido)
    print("listo")

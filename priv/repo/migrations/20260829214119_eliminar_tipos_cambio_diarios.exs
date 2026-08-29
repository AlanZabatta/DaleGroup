defmodule DaleApp.Repo.Migrations.EliminarTiposCambioDiarios do
  use Ecto.Migration

  def change do
    # Tabla del viejo sistema de tipo de cambio entre Ventas y Gestores,
    # reemplazado por monedas separadas (movimientos_puntos + SaldoPuntos).
    # Nadie la usa desde el codigo, y estaba vacia al momento de borrarla.
    drop table(:tipos_cambio_diarios)
  end
end

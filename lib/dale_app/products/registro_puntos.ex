defmodule DaleApp.Products.RegistroPuntos do
  @moduledoc """
  UNICO lugar del sistema autorizado a escribir puntos ganados.

  Si los puntos se pudieran crear desde varios lados, tarde o temprano uno
  se olvida de aplicar el multiplicador y quedan filas mal calculadas que
  nadie detecta hasta que un empleado reclama. Todo pasa por aca.

  El multiplicador solo se aplica a Gestores. Ventas es la referencia y
  siempre vale 1.0: sus puntos crudos y finales son el mismo numero.
  """
  alias DaleApp.Repo
  alias DaleApp.Products.{MovimientoPuntos, Puntos}

  @doc """
  Registra puntos ganados. Devuelve {:ok, movimiento}, {:ok, :duplicado} si
  ese hecho ya habia pagado, o {:error, motivo}.

  El que llama NUNCA debe abortar su propia operacion por un error de aca:
  si un empleado carga stock y el registro de puntos falla, el stock tiene
  que quedar guardado igual. Es preferible un punto faltante que un item
  que no se cargo.
  """
  def registrar(brand, usuario, motivo, puntos_crudos, opciones \\ [])

  def registrar(_brand, _usuario, _motivo, puntos_crudos, _opciones)
      when not is_integer(puntos_crudos) or puntos_crudos <= 0 do
    {:error, :puntos_invalidos}
  end

  def registrar(brand, usuario, motivo, puntos_crudos, opciones)
      when not is_nil(brand) and not is_nil(usuario) do
    categoria = Puntos.categoria_del_usuario(usuario)
    multiplicador = multiplicador_de(brand, categoria)

    attrs = %{
      brand_id: brand.id,
      user_id: usuario.id,
      motivo: motivo,
      categoria: categoria,
      puntos_crudos: puntos_crudos,
      multiplicador: multiplicador,
      puntos_finales: round(puntos_crudos * multiplicador),
      origen_tipo: Keyword.get(opciones, :origen_tipo),
      origen_id: Keyword.get(opciones, :origen_id),
      fecha: Date.utc_today()
    }

    %MovimientoPuntos{}
    |> MovimientoPuntos.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, movimiento} ->
        {:ok, movimiento}

      # El indice unico rechazo la fila: ese hecho ya habia pagado puntos.
      # No es un error, es la proteccion funcionando.
      {:error, %Ecto.Changeset{errors: errores}} ->
        if Keyword.has_key?(errores, :origen_tipo) or Keyword.has_key?(errores, :origen_id) do
          {:ok, :duplicado}
        else
          {:error, errores}
        end
    end
  end

  def registrar(_brand, _usuario, _motivo, _puntos_crudos, _opciones), do: {:error, :faltan_datos}

  # Ventas es la referencia: siempre 1.0. Gestores lleva el factor calculado
  # de la marca. OJO: el factor se calcula sobre puntos CRUDOS (ver Puntos),
  # nunca sobre los ya multiplicados, o el sistema se retroalimenta y oscila.
  defp multiplicador_de(_brand, "ventas"), do: 1.0

  defp multiplicador_de(brand, "gestores") do
    case Puntos.factor_vigente(brand) do
      factor when is_number(factor) and factor > 0 -> factor * 1.0
      _ -> 1.0
    end
  end
end

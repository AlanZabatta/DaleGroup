defmodule DaleApp.Products.Dale9 do
  @moduledoc """
  Logica de negocio del sistema DALE9: asignacion y reciclado de numeros
  de producto (los 3 digitos "PPP" del codigo, unicos por marca+tipo).
  """
  import Ecto.Query, only: [from: 2]
  alias DaleApp.Repo
  alias DaleApp.Products.{Product, NumeroLiberado}

  @dias_reciclado 120

  @doc """
  Devuelve el proximo numero de producto disponible (3 digitos, string)
  para una marca y tipo de prenda dados. Reutiliza numeros liberados
  hace mas de 120 dias antes de crear uno nuevo.
  """
  def proximo_numero(brand_id, codigo_tipo) do
    limite = DateTime.utc_now() |> DateTime.add(-@dias_reciclado * 86400, :second)

    reciclable =
      from(nl in NumeroLiberado,
        where: nl.brand_id == ^brand_id and nl.codigo_tipo == ^codigo_tipo and nl.liberado_en <= ^limite,
        order_by: [asc: nl.codigo_numero],
        limit: 1
      )
      |> Repo.one()

    case reciclable do
      %NumeroLiberado{codigo_numero: numero} = registro ->
        Repo.delete(registro)
        numero

      nil ->
        siguiente_numero_nuevo(brand_id, codigo_tipo)
    end
  end

  defp siguiente_numero_nuevo(brand_id, codigo_tipo) do
    usados =
      from(p in Product,
        where: p.brand_id == ^brand_id and p.codigo_tipo == ^codigo_tipo,
        select: p.codigo_numero
      )
      |> Repo.all()
      |> Enum.map(&String.to_integer/1)
      |> MapSet.new()

    Enum.find(1..999, fn n -> not MapSet.member?(usados, n) end)
    |> case do
      nil -> {:error, :sin_numeros_disponibles}
      n -> n |> Integer.to_string() |> String.pad_leading(3, "0")
    end
  end

  @doc """
  Marca un numero de producto como liberado (para reciclar despues de 120 dias),
  se llama cuando se borra un producto que ya tenia codigo asignado.
  """
  def liberar_numero(brand_id, codigo_tipo, codigo_numero) do
    %NumeroLiberado{}
    |> NumeroLiberado.changeset(%{
      brand_id: brand_id,
      codigo_tipo: codigo_tipo,
      codigo_numero: codigo_numero,
      liberado_en: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end
end

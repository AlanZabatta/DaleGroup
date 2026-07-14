defmodule DaleApp.Products do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Products.Product

  def list_brand_products(brand_id) do
    Repo.all(from p in Product, where: p.brand_id == ^brand_id, order_by: p.position_in_brand)
  end

  def get_product(id), do: Repo.get(Product, id)

  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(product), do: Repo.delete(product)

  def ensure_brand_slots(brand_id) do
    existing = list_brand_products(brand_id)
    existing_count = length(existing)
    slots_needed = 10 - existing_count

    if slots_needed > 0 do
      for i <- (existing_count + 1)..(existing_count + slots_needed) do
        create_product(%{brand_id: brand_id, position_in_brand: i})
      end
    end
  end

  # Busqueda y filtrado de productos (buscador + filtros)
  # opts: %{texto, genero, estilo, categoria, precio_min, precio_max, orden}
  def buscar_productos(opts \\ %{}) do
    query =
      from p in Product,
      join: b in DaleApp.Brands.Brand, on: p.brand_id == b.id,
      where: p.active == true and not is_nil(p.image) and b.active == true,
      select: %{producto: p, marca: b}

    query = aplicar_genero(query, Map.get(opts, :genero))
    query = aplicar_estilo(query, Map.get(opts, :estilo))
    query = aplicar_categoria(query, Map.get(opts, :categoria))
    query = aplicar_precio(query, Map.get(opts, :precio_min), Map.get(opts, :precio_max))
    query = aplicar_nivel_precio(query, Map.get(opts, :nivel))

    texto = Map.get(opts, :texto)
    query_normal = aplicar_texto(query, texto)
    resultados = Repo.all(query_normal)

    resultados =
      if resultados == [] and is_binary(texto) and String.trim(texto) != "" do
        Repo.all(aplicar_texto_fuzzy(query, texto))
      else
        resultados
      end

    aplicar_orden(resultados, Map.get(opts, :orden))
  end

  defp aplicar_texto(query, nil), do: query
  defp aplicar_texto(query, ""), do: query
  defp aplicar_texto(query, texto) do
    patron = "%" <> String.downcase(String.trim(texto)) <> "%"
    from [p, b] in query,
      where: like(fragment("lower(?)", p.name), ^patron) or
             like(fragment("lower(?)", b.name), ^patron)
  end

  defp aplicar_texto_fuzzy(query, texto) do
    limpio = String.downcase(String.trim(texto))
    from [p, b] in query,
      where: fragment("word_similarity(?, lower(?)) > 0.3", ^limpio, p.name) or
             fragment("word_similarity(?, lower(?)) > 0.3", ^limpio, b.name),
      order_by: [desc: fragment("word_similarity(?, lower(?))", ^limpio, p.name)]
  end

  defp aplicar_genero(query, nil), do: query
  defp aplicar_genero(query, ""), do: query
  defp aplicar_genero(query, genero) do
    from [p, b] in query, where: p.gender == ^genero
  end

  defp aplicar_estilo(query, nil), do: query
  defp aplicar_estilo(query, ""), do: query
  defp aplicar_estilo(query, estilo) do
    from [p, b] in query, where: p.estilo == ^estilo
  end

  defp aplicar_categoria(query, nil), do: query
  defp aplicar_categoria(query, ""), do: query
  defp aplicar_categoria(query, categoria) do
    from [p, b] in query, where: ^categoria in p.categorias
  end

  defp aplicar_precio(query, nil, nil), do: query

  defp aplicar_precio(query, min, nil) do
    from [p, b] in query, where: p.price >= ^min
  end

  defp aplicar_precio(query, nil, max) do
    from [p, b] in query, where: p.price <= ^max
  end

  defp aplicar_precio(query, min, max) do
    from [p, b] in query, where: p.price >= ^min and p.price <= ^max
  end

  defp aplicar_orden(resultados, "menor_mayor"), do: Enum.sort_by(resultados, fn %{producto: p} -> p.price || 0 end)
  defp aplicar_orden(resultados, "mayor_menor"), do: Enum.sort_by(resultados, fn %{producto: p} -> -(p.price || 0) end)
  defp aplicar_orden(resultados, _), do: resultados


  def rangos_precio do
    precios = Repo.all(from p in Product, where: p.active == true and not is_nil(p.price), select: p.price, order_by: [asc: p.price])
    case precios do
      [] -> %{t1: 0, t2: 0}
      _ ->
        n = length(precios)
        %{t1: Enum.at(precios, max(div(n,3)-1,0)), t2: Enum.at(precios, max(div(2*n,3)-1,0))}
    end
  end
  defp aplicar_nivel_precio(query, nil), do: query
  defp aplicar_nivel_precio(query, ""), do: query
  defp aplicar_nivel_precio(query, "1") do
    %{t1: t1} = rangos_precio()
    from [p, b] in query, where: p.price <= ^t1
  end
  defp aplicar_nivel_precio(query, "2") do
    %{t1: t1, t2: t2} = rangos_precio()
    from [p, b] in query, where: p.price > ^t1 and p.price <= ^t2
  end
  defp aplicar_nivel_precio(query, "3") do
    %{t2: t2} = rangos_precio()
    from [p, b] in query, where: p.price > ^t2
  end
  defp aplicar_nivel_precio(query, _), do: query
end

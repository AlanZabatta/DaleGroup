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
end

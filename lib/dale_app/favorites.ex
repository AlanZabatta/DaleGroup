defmodule DaleApp.Favorites do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Favorites.Favorite

  def toggle(user_id, product_id) do
    case Repo.get_by(Favorite, user_id: user_id, product_id: product_id) do
      nil ->
        %Favorite{}
        |> Favorite.changeset(%{user_id: user_id, product_id: product_id})
        |> Repo.insert()
        {:ok, :added}
      fav ->
        Repo.delete(fav)
        {:ok, :removed}
    end
  end

  def favorited?(user_id, product_id) do
    Repo.exists?(from f in Favorite, where: f.user_id == ^user_id and f.product_id == ^product_id)
  end

  def list_user_favorites(user_id) do
    Repo.all(from f in Favorite, where: f.user_id == ^user_id, preload: [:product])
  end

  def count_by_product(product_id) do
    Repo.aggregate(from(f in Favorite, where: f.product_id == ^product_id), :count)
  end
end

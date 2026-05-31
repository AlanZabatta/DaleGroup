defmodule DaleApp.MapSaves do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.MapSaves.MapSave

  def add_to_map(user_id, brand_id) do
    expires_at = DateTime.utc_now() |> DateTime.add(48 * 3600, :second) |> DateTime.truncate(:second)
    %MapSave{}
    |> MapSave.changeset(%{user_id: user_id, brand_id: brand_id, expires_at: expires_at})
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :brand_id])
  end

  def remove_from_map(user_id, brand_id) do
    Repo.delete_all(from m in MapSave, where: m.user_id == ^user_id and m.brand_id == ^brand_id)
  end

  def list_user_map(user_id) do
    now = DateTime.utc_now()
    Repo.all(from m in MapSave, where: m.user_id == ^user_id and m.expires_at > ^now, preload: [:brand])
  end

  def clean_expired do
    now = DateTime.utc_now()
    Repo.delete_all(from m in MapSave, where: m.expires_at <= ^now)
  end
end

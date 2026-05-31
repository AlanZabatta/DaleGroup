defmodule DaleAppWeb.PageController do
  use DaleAppWeb, :controller
  import Ecto.Query
  alias DaleApp.Accounts

  def home(conn, _params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    render(conn, :home, current_user: current_user)
  end

  def mapa(conn, _params) do
    user_id = get_session(conn, :user_id)
    marcas = DaleApp.Repo.all(
      from b in DaleApp.Brands.Brand,
      where: b.active == true and not is_nil(b.latitude)
    )
    saved_brand_ids = if user_id do
      DaleApp.MapSaves.list_user_map(user_id) |> Enum.map(& &1.brand_id)
    else
      []
    end
    render(conn, :mapa, marcas: marcas, saved_brand_ids: saved_brand_ids)
  end
end

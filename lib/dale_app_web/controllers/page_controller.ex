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
    marcas = DaleApp.Repo.all(
      from b in DaleApp.Brands.Brand,
      where: b.active == true and not is_nil(b.address)
    )
    render(conn, :mapa, marcas: marcas)
  end
end

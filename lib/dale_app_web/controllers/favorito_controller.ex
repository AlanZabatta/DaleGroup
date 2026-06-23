defmodule DaleAppWeb.FavoritoController do
  use DaleAppWeb, :controller
  alias DaleApp.Favorites

  def toggle(conn, %{"product_id" => product_id}) do
    user_id = get_session(conn, :user_id)
    if user_id do
      {:ok, action} = Favorites.toggle(user_id, String.to_integer(product_id))
      json(conn, %{ok: true, action: to_string(action)})
    else
      json(conn, %{ok: false, error: "not_logged_in"})
    end
  end
end

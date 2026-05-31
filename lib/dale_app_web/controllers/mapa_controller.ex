defmodule DaleAppWeb.MapaController do
  use DaleAppWeb, :controller
  alias DaleApp.MapSaves

  def agregar(conn, %{"brand_id" => brand_id}) do
    user_id = get_session(conn, :user_id)
    if user_id do
      MapSaves.add_to_map(user_id, String.to_integer(brand_id))
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false, error: "Necesitás iniciar sesión"})
    end
  end

  def quitar(conn, %{"brand_id" => brand_id}) do
    user_id = get_session(conn, :user_id)
    if user_id do
      MapSaves.remove_from_map(user_id, String.to_integer(brand_id))
      json(conn, %{ok: true})
    else
      json(conn, %{ok: false})
    end
  end
end

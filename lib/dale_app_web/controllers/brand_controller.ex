defmodule DaleAppWeb.BrandController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mi_tienda(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    render(conn, :mi_tienda, brand: brand)
  end

  def update(conn, %{"brand" => brand_params}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    brand
    |> Brand.changeset(brand_params)
    |> Repo.update()

    conn
    |> put_flash(:info, "Tienda actualizada.")
    |> redirect(to: ~p"/mi-tienda")
  end
end

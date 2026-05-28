defmodule DaleAppWeb.BrandController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Accounts

  def mi_tienda(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    render(conn, :mi_tienda, brand: brand, cajeros: cajeros)
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

  def cajeros(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cajeros = if brand, do: Accounts.list_cajeros(brand.id), else: []
    render(conn, :cajeros, brand: brand, cajeros: cajeros)
  end

  def remove_cajero(conn, %{"id" => id}) do
    user = Accounts.get_user(id)
    Accounts.remove_cajero(user)

    conn
    |> put_flash(:info, "Cajero eliminado.")
    |> redirect(to: ~p"/mi-tienda/cajeros")
  end

  def unirse(conn, %{"brand_id" => brand_id}) do
    user_id = get_session(conn, :user_id)

    if is_nil(user_id) do
      conn
      |> put_session(:join_brand_id, brand_id)
      |> redirect(to: ~p"/auth/google")
    else
      user = Accounts.get_user(user_id)
      brand = Repo.get(Brand, brand_id)

      case Accounts.assign_cajero(user, String.to_integer(brand_id)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Ahora sos cajero de #{brand.name}.")
          |> redirect(to: ~p"/")
        {:error, _} ->
          conn
          |> put_flash(:error, "Error al unirse.")
          |> redirect(to: ~p"/")
      end
    end
  end
end

defmodule DaleAppWeb.AuthController do
  use DaleAppWeb, :controller
  plug Ueberauth

  def request(conn, _params) do
    render(conn, :request)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      email: auth.info.email,
      name: auth.info.name,
      avatar: auth.info.image,
      google_id: auth.uid
    }

    case DaleApp.Accounts.find_or_create_user(user_params) do
      {:ok, user} ->
        join_brand_id = get_session(conn, :join_brand_id)

        conn = conn
        |> put_session(:user_id, user.id)
        |> delete_session(:join_brand_id)

        if join_brand_id do
          DaleApp.Accounts.assign_cajero(user, String.to_integer(join_brand_id))
          brand = DaleApp.Repo.get(DaleApp.Brands.Brand, join_brand_id)
          conn
          |> put_flash(:info, "Bienvenido #{user.name}! Ahora sos cajero de #{brand.name}.")
          |> redirect(to: ~p"/")
        else
          conn
          |> put_flash(:info, "Bienvenido #{user.name}!")
          |> redirect(to: ~p"/")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error al iniciar sesión.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Error al iniciar sesión con Google.")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Sesión cerrada.")
    |> redirect(to: ~p"/")
  end
end

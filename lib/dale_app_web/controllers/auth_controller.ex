defmodule DaleAppWeb.AuthController do
  use DaleAppWeb, :controller
  plug Ueberauth
  def request(conn, _params) do
    render(conn, :request)
  end
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    provider = auth.provider

    existing_user =
      case provider do
        :google -> DaleApp.Accounts.find_user_by_google(auth.uid)
        :discord -> DaleApp.Accounts.find_user_by_discord(auth.uid)
        _ -> nil
      end

    case existing_user do
      nil ->
        conn
        |> put_session(:auth_pendiente, %{
          "email" => auth.info.email,
          "name" => auth.info.name,
          "avatar" => auth.info.image,
          "provider" => Atom.to_string(provider),
          "uid" => auth.uid
        })
        |> redirect(to: ~p"/registro")

      user ->
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
    end
  end
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Error al iniciar sesión.")
    |> redirect(to: ~p"/")
  end
  def finalizar(conn, %{"user_id" => user_id}) do
    user = DaleApp.Accounts.get_user(user_id)

    conn
    |> put_session(:user_id, user.id)
    |> delete_session(:auth_pendiente)
    |> put_flash(:info, "Bienvenido #{user.name}!")
    |> redirect(to: ~p"/")
  end
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Sesión cerrada.")
    |> redirect(to: ~p"/")
  end
end

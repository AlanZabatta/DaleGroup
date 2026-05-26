defmodule DaleAppWeb.AdminController do
  use DaleAppWeb, :controller

  alias DaleApp.Accounts

  def index(conn, _params) do
    users = Accounts.list_users()
    render(conn, :index, users: users)
  end

  def update_role(conn, %{"id" => id, "role" => role}) do
    user = Accounts.get_user(id)
    Accounts.update_user_role(user, role)

    conn
    |> put_flash(:info, "Rol actualizado.")
    |> redirect(to: ~p"/admin")
  end

  def ban(conn, %{"id" => id}) do
    user = Accounts.get_user(id)
    Accounts.ban_user(user)

    conn
    |> put_flash(:info, "Usuario baneado.")
    |> redirect(to: ~p"/admin")
  end
end

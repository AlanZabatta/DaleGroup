defmodule DaleAppWeb.Plugs.SetCurrentUser do
  import Plug.Conn
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: DaleApp.Accounts.get_user(user_id), else: nil
    mi_marca_id = if current_user, do: obtener_mi_marca_id(current_user.id), else: nil

    conn
    |> assign(:current_user, current_user)
    |> assign(:mi_marca_id, mi_marca_id)
  end

  defp obtener_mi_marca_id(user_id) do
    case Repo.get_by(Brand, user_id: user_id) do
      nil -> nil
      brand -> brand.id
    end
  end
end

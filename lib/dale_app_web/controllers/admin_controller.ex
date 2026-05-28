defmodule DaleAppWeb.AdminController do
  use DaleAppWeb, :controller

  alias DaleApp.Accounts
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Events
  import Ecto.Query

  def index(conn, _params) do
    users = Accounts.list_users()
    brands = Repo.all(Brand)
    render(conn, :index, users: users, brands: brands)
  end

  def stats(conn, _params) do
    brands = Repo.all(Brand)

    brand_stats = Enum.map(brands, fn brand ->
      %{
        brand: brand,
        stats_30: Events.brand_stats_days(brand.id, 30),
        stats_90: Events.brand_stats_days(brand.id, 90),
        stats_all: Events.brand_stats(brand.id)
      }
    end)

    global_30 = Events.global_stats_days(30)
    global_90 = Events.global_stats_days(90)
    global_all = Events.global_stats()

    render(conn, :stats,
      brand_stats: brand_stats,
      global_30: global_30,
      global_90: global_90,
      global_all: global_all
    )
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

  def disable_brand(conn, %{"id" => id}) do
    brand = Repo.get(Brand, id)
    brand
    |> Brand.changeset(%{active: false})
    |> Repo.update()

    conn
    |> put_flash(:info, "Tienda desactivada.")
    |> redirect(to: ~p"/admin")
  end
end

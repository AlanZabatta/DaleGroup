defmodule DaleAppWeb.MarcasController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Coupons.Coupon
  alias DaleApp.Events
  import Ecto.Query

  def index(conn, _params) do
    marcas = Repo.all(from b in Brand, where: b.active == true)
    render(conn, :index, marcas: marcas)
  end

  def show(conn, %{"id" => id}) do
    marca = Repo.get!(Brand, id)
    cupon = Repo.one(from c in Coupon, where: c.brand_id == ^marca.id and c.active == true, limit: 1)

    user_id = get_session(conn, :user_id)
    Events.track("brand_view", user_id, marca.id, %{brand_name: marca.name})

    render(conn, :show, marca: marca, cupon: cupon)
  end
end

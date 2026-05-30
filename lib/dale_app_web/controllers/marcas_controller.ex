defmodule DaleAppWeb.MarcasController do
  use DaleAppWeb, :controller
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Coupons.Coupon
  alias DaleApp.Events
  alias DaleApp.Products
  import Ecto.Query

  def index(conn, _params) do
    marcas = Repo.all(from b in Brand, where: b.active == true)
    render(conn, :index, marcas: marcas)
  end

  def show(conn, %{"id" => id}) do
    marca = Repo.get!(Brand, id)
    cupon = Repo.one(from c in Coupon, where: c.brand_id == ^marca.id and c.active == true, limit: 1)
    user_id = get_session(conn, :user_id)
    current_user = conn.assigns[:current_user]

    if current_user && current_user.role == "dueño" && current_user.id == marca.user_id do
      Products.ensure_brand_slots(marca.id)
    end

    productos = Products.list_brand_products(marca.id)
    Events.track("brand_view", user_id, marca.id, %{brand_name: marca.name})
    render(conn, :show, marca: marca, cupon: cupon, productos: productos)
  end
end

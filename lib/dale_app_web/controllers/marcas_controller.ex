defmodule DaleAppWeb.MarcasController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand
  alias DaleApp.Coupons.Coupon
  import Ecto.Query

  def index(conn, _params) do
    marcas = Repo.all(Brand)
    render(conn, :index, marcas: marcas)
  end

  def show(conn, %{"id" => id}) do
    marca = Repo.get!(Brand, id)
    cupon = Repo.one(from c in Coupon, where: c.brand_id == ^marca.id and c.active == true, limit: 1)
    render(conn, :show, marca: marca, cupon: cupon)
  end
end

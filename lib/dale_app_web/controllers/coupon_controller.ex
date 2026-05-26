defmodule DaleAppWeb.CouponController do
  use DaleAppWeb, :controller

  alias DaleApp.Repo
  alias DaleApp.Coupons.Coupon
  alias DaleApp.Brands.Brand

  def new(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    render(conn, :new, brand: brand)
  end

  def create(conn, %{"coupon" => coupon_params}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)

    %Coupon{}
    |> Coupon.changeset(Map.put(coupon_params, "brand_id", brand.id))
    |> Repo.insert()

    conn
    |> put_flash(:info, "Cupón creado.")
    |> redirect(to: ~p"/mi-tienda")
  end
end

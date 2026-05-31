defmodule DaleAppWeb.CouponController do
  use DaleAppWeb, :controller
  alias DaleApp.Repo
  alias DaleApp.Coupons.Coupon
  alias DaleApp.Brands.Brand
  import Ecto.Query

  def new(conn, _params) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cupon = if brand, do: Repo.one(from c in Coupon, where: c.brand_id == ^brand.id, limit: 1), else: nil
    render(conn, :new, brand: brand, cupon: cupon)
  end

  def create(conn, %{"coupon" => coupon_params}) do
    user_id = get_session(conn, :user_id)
    brand = Repo.get_by(Brand, user_id: user_id)
    cupon = Repo.one(from c in Coupon, where: c.brand_id == ^brand.id, limit: 1)

    if cupon do
      cupon
      |> Coupon.changeset(coupon_params)
      |> Repo.update()
    else
      %Coupon{}
      |> Coupon.changeset(Map.put(coupon_params, "brand_id", brand.id))
      |> Repo.insert()
    end

    conn
    |> put_flash(:info, "Cupón guardado.")
    |> redirect(to: ~p"/mi-stand")
  end
end

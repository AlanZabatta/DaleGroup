defmodule DaleAppWeb.ClaimController do
  use DaleAppWeb, :controller
  alias DaleApp.Claims
  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def create(conn, %{"coupon_id" => coupon_id, "brand_id" => brand_id}) do
    user_id = get_session(conn, :user_id)

    if is_nil(user_id) do
      conn
      |> put_flash(:error, "Necesitás iniciar sesión para reclamar beneficios.")
      |> redirect(to: "/auth/google")
    else
      case Claims.create_claim(user_id, String.to_integer(coupon_id), String.to_integer(brand_id)) do
        {:ok, claim} ->
          render(conn, :show, claim: claim)
        {:error, _} ->
          conn
          |> put_flash(:error, "Error al reclamar el cupón.")
          |> redirect(to: ~p"/marcas/#{brand_id}")
      end
    end
  end

  def redeem(conn, params) do
    user_id = get_session(conn, :user_id)
    current_user = DaleApp.Accounts.get_user(user_id)
    is_admin = current_user && current_user.role == "admin"
    cajero_brand = if is_admin, do: nil, else: Repo.get_by(Brand, user_id: user_id)

    case params do
      %{"code" => code} ->
        claim = Claims.get_claim_by_code(code)

        cond do
          is_nil(claim) ->
            render(conn, :result, message: "QR inválido", success: false, discount: nil)

          is_admin ->
            case Claims.redeem_claim_admin(claim) do
              {:ok, _} ->
                brand = Repo.get(Brand, claim.brand_id)
                render(conn, :result, message: "Canjeado! +100 puntos al usuario", success: true, discount: brand && brand.discount)
              {:error, :already_redeemed} ->
                render(conn, :result, message: "Este cupón ya fue canjeado", success: false, discount: nil)
              {:error, :expired} ->
                render(conn, :result, message: "Este cupón venció (más de 12hs)", success: false, discount: nil)
            end

          is_nil(cajero_brand) ->
            render(conn, :result, message: "No tenés una marca asignada", success: false, discount: nil)

          true ->
            case Claims.redeem_claim(claim, cajero_brand.id) do
              {:ok, _} ->
                render(conn, :result, message: "Canjeado! +100 puntos al usuario", success: true, discount: cajero_brand.discount)
              {:error, :wrong_brand} ->
                render(conn, :result, message: "Este QR es de otra marca", success: false, discount: nil)
              {:error, :already_redeemed} ->
                render(conn, :result, message: "Este cupón ya fue canjeado", success: false, discount: nil)
              {:error, :expired} ->
                render(conn, :result, message: "Este cupón venció (más de 12hs)", success: false, discount: nil)
            end
        end

      _ ->
        render(conn, :scanner, is_admin: is_admin)
    end
  end
end

defmodule DaleApp.Claims do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Claims.Claim
  alias DaleApp.Accounts.User

  def create_claim(user_id, coupon_id, brand_id) do
    expires_at = DateTime.utc_now() |> DateTime.add(12 * 3600, :second) |> DateTime.truncate(:second)
    code = :crypto.strong_rand_bytes(16) |> Base.encode16()

    %Claim{}
    |> Claim.changeset(%{
      code: code,
      status: "pending",
      claimed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      expires_at: expires_at,
      user_id: user_id,
      coupon_id: coupon_id,
      brand_id: brand_id
    })
    |> Repo.insert()
  end

  def get_claim_by_code(code) do
    Repo.one(from c in Claim, where: c.code == ^code)
  end

  def redeem_claim(claim, cajero_brand_id) do
    cond do
      claim.brand_id != cajero_brand_id ->
        {:error, :wrong_brand}
      claim.status == "redeemed" ->
        {:error, :already_redeemed}
      DateTime.compare(DateTime.utc_now(), claim.expires_at) == :gt ->
        {:error, :expired}
      true ->
        do_redeem(claim)
    end
  end

  def redeem_claim_admin(claim) do
    cond do
      claim.status == "redeemed" ->
        {:error, :already_redeemed}
      DateTime.compare(DateTime.utc_now(), claim.expires_at) == :gt ->
        {:error, :expired}
      true ->
        do_redeem(claim)
    end
  end

  defp do_redeem(claim) do
    claim
    |> Claim.changeset(%{
      status: "redeemed",
      redeemed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, claim} ->
        user = Repo.get(User, claim.user_id)
        user
        |> User.changeset(%{points: (user.points || 0) + 100})
        |> Repo.update()
        {:ok, claim}
      error -> error
    end
  end
end

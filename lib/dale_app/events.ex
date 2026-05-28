defmodule DaleApp.Events do
  alias DaleApp.Repo
  alias DaleApp.Events.Event
  import Ecto.Query

  def track(type, user_id \\ nil, brand_id \\ nil, metadata \\ %{}) do
    %Event{}
    |> Event.changeset(%{
      type: type,
      user_id: user_id,
      brand_id: brand_id,
      metadata: metadata
    })
    |> Repo.insert()
  end

  def brand_stats(brand_id) do
    views = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "brand_view"), :count)
    claims = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_claim"), :count)
    redeems = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_redeem"), :count)
    %{views: views, claims: claims, redeems: redeems}
  end

  def brand_stats_days(brand_id, days) do
    since = DateTime.utc_now() |> DateTime.add(-days * 86400, :second) |> DateTime.truncate(:second)
    views = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "brand_view" and e.inserted_at >= ^since), :count)
    claims = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_claim" and e.inserted_at >= ^since), :count)
    redeems = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_redeem" and e.inserted_at >= ^since), :count)
    %{views: views, claims: claims, redeems: redeems}
  end

  def global_stats() do
    views = Repo.aggregate(from(e in Event, where: e.type == "brand_view"), :count)
    claims = Repo.aggregate(from(e in Event, where: e.type == "coupon_claim"), :count)
    redeems = Repo.aggregate(from(e in Event, where: e.type == "coupon_redeem"), :count)
    users = Repo.aggregate(from(e in Event, where: e.type == "brand_view"), :count, :user_id)
    %{views: views, claims: claims, redeems: redeems, unique_users: users}
  end

  def global_stats_days(days) do
    since = DateTime.utc_now() |> DateTime.add(-days * 86400, :second) |> DateTime.truncate(:second)
    views = Repo.aggregate(from(e in Event, where: e.type == "brand_view" and e.inserted_at >= ^since), :count)
    claims = Repo.aggregate(from(e in Event, where: e.type == "coupon_claim" and e.inserted_at >= ^since), :count)
    redeems = Repo.aggregate(from(e in Event, where: e.type == "coupon_redeem" and e.inserted_at >= ^since), :count)
    %{views: views, claims: claims, redeems: redeems}
  end

  def top_brands(limit \\ 10) do
    Repo.all(
      from e in Event,
      where: e.type == "brand_view",
      group_by: e.brand_id,
      order_by: [desc: count(e.id)],
      select: {e.brand_id, count(e.id)},
      limit: ^limit
    )
  end

  def user_events(user_id) do
    Repo.all(from e in Event, where: e.user_id == ^user_id, order_by: [desc: e.inserted_at])
  end
end

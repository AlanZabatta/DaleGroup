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

  def brand_views(brand_id) do
    Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "brand_view"), :count)
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

  def brand_stats(brand_id) do
    views = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "brand_view"), :count)
    claims = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_claim"), :count)
    redeems = Repo.aggregate(from(e in Event, where: e.brand_id == ^brand_id and e.type == "coupon_redeem"), :count)

    %{views: views, claims: claims, redeems: redeems}
  end
end

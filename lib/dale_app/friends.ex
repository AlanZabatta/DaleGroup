defmodule DaleApp.Friends do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts.User

  defmodule Friendship do
    use Ecto.Schema
    import Ecto.Changeset

    schema "friendships" do
      belongs_to :requester, User
      belongs_to :addressee, User
      field :status, :string, default: "pending"
      timestamps()
    end

    def changeset(f, attrs) do
      f
      |> cast(attrs, [:requester_id, :addressee_id, :status])
      |> validate_required([:requester_id, :addressee_id])
      |> unique_constraint([:requester_id, :addressee_id])
    end
  end

  def find_by_username(username, current_user_id) do
    user = Repo.get_by(User, username: username)
    if user && user.id != current_user_id, do: user, else: nil
  end

  def send_request(requester_id, addressee_id) do
    existing = Repo.one(
      from f in Friendship,
      where: (f.requester_id == ^requester_id and f.addressee_id == ^addressee_id)
          or (f.requester_id == ^addressee_id and f.addressee_id == ^requester_id)
    )

    case existing do
      nil ->
        %Friendship{}
        |> Friendship.changeset(%{requester_id: requester_id, addressee_id: addressee_id, status: "pending"})
        |> Repo.insert()
      _ ->
        {:error, :exists}
    end
  end

  def accept_request(friendship_id, user_id) do
    case Repo.get(Friendship, friendship_id) do
      %Friendship{addressee_id: ^user_id} = f ->
        f |> Friendship.changeset(%{status: "accepted"}) |> Repo.update()
      _ ->
        {:error, :not_found}
    end
  end

  def reject_request(friendship_id, user_id) do
    case Repo.get(Friendship, friendship_id) do
      %Friendship{addressee_id: ^user_id} = f ->
        Repo.delete(f)
      %Friendship{requester_id: ^user_id} = f ->
        Repo.delete(f)
      _ ->
        {:error, :not_found}
    end
  end

  def pending_requests(user_id) do
    Repo.all(
      from f in Friendship,
      where: f.addressee_id == ^user_id and f.status == "pending",
      preload: [:requester]
    )
  end

  def friends_list(user_id) do
    Repo.all(
      from f in Friendship,
      where: (f.requester_id == ^user_id or f.addressee_id == ^user_id) and f.status == "accepted",
      preload: [:requester, :addressee]
    )
    |> Enum.map(fn f ->
      if f.requester_id == user_id, do: f.addressee, else: f.requester
    end)
  end

  def relation_status(user_id, other_id) do
    Repo.one(
      from f in Friendship,
      where: (f.requester_id == ^user_id and f.addressee_id == ^other_id)
          or (f.requester_id == ^other_id and f.addressee_id == ^user_id)
    )
  end
end

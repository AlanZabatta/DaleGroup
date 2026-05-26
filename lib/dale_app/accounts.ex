
defmodule DaleApp.Accounts do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts.User
  alias DaleApp.Brands.Brand

  def find_or_create_user(%{email: email} = params) do
    case Repo.get_by(User, email: email) do
      nil ->
        %User{}
        |> User.changeset(params)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def get_user(id), do: Repo.get(User, id)

  def update_user_role(user, role) do
    result =
      user
      |> User.changeset(%{role: role})
      |> Repo.update()

    if role == "dueño" do
      case Repo.get_by(Brand, user_id: user.id) do
        nil ->
          %Brand{}
          |> Brand.changeset(%{
            name: user.name || "Mi Tienda",
            user_id: user.id
          })
          |> Repo.insert()
        _ -> :ok
      end
    end

    result
  end

  def ban_user(user) do
    user
    |> User.changeset(%{banned: true})
    |> Repo.update()
  end

  def list_users do
    Repo.all(User)
  end
end

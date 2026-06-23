defmodule DaleApp.Accounts do
  import Ecto.Query
  alias DaleApp.Repo
  alias DaleApp.Accounts.User
  alias DaleApp.Brands.Brand

  def find_or_create_user(%{email: email} = params) do
    case Repo.get_by(User, email: email) do
      nil ->
        %User{}
        |> User.changeset(Map.put(params, :username, generate_username()))
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

  def assign_cajero(user, brand_id) do
    user
    |> User.changeset(%{role: "cajero", cajero_brand_id: brand_id})
    |> Repo.update()
  end

  def remove_cajero(user) do
    user
    |> User.changeset(%{role: "user", cajero_brand_id: nil})
    |> Repo.update()
  end

  def list_cajeros(brand_id) do
    Repo.all(from u in User, where: u.cajero_brand_id == ^brand_id)
  end

  def generate_username do
    code = generate_code()
    username = "User" <> code
    if Repo.get_by(User, username: username) do
      generate_username()
    else
      username
    end
  end

  defp generate_code do
    digits = for _ <- 1..7, do: Enum.random(1..9)
    counts = Enum.frequencies(digits)
    if Enum.any?(counts, fn {_d, c} -> c > 2 end) do
      generate_code()
    else
      Enum.join(digits)
    end
  end

end

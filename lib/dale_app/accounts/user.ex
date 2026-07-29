defmodule DaleApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string
    field :role, :string, default: "user"
    field :banned, :boolean, default: false
    field :google_id, :string
    field :discord_id, :string
    field :points, :integer, default: 0
    field :is_referral, :boolean, default: false
    field :username, :string
    field :username_changed_at, :naive_datetime
    field :friend_code, :string
    field :perfil_config, :map, default: %{}
    field :telefono, :string
    field :sede, :string
    field :zona, :string
    field :horario_laboral, :string
    field :nombre_visible, :string
    field :apellido_visible, :string
    field :puntos_empleo, :integer, default: 0
    belongs_to :referral_brand, DaleApp.Brands.Brand, foreign_key: :referral_brand_id
    belongs_to :cajero_brand, DaleApp.Brands.Brand, foreign_key: :cajero_brand_id
    belongs_to :horario, DaleApp.Brands.HorarioTrabajo, foreign_key: :horario_id

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar, :role, :banned, :google_id, :discord_id, :points, :is_referral, :referral_brand_id, :cajero_brand_id, :username, :friend_code, :username_changed_at, :perfil_config, :telefono, :sede, :zona, :horario_laboral, :nombre_visible, :apellido_visible, :puntos_empleo, :horario_id])
    |> unique_constraint(:username)
    |> validate_required([:email])
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
    |> unique_constraint(:discord_id)
  end
end

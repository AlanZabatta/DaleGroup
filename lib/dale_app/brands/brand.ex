defmodule DaleApp.Brands.Brand do
  use Ecto.Schema
  import Ecto.Changeset

  schema "brands" do
    field :name, :string
    field :logo, :string
    field :cover_image, :string
    field :description, :string
    field :address, :string
    field :address_full, :string
    field :horario_atencion, :string
    field :colores, :map, default: %{}
    field :asistencia_activa, :boolean, default: false
    field :asistencia_activada_en, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :image_limit, :integer, default: 12
    field :active, :boolean, default: true
    field :modalidad, :string, default: "presencial"
    field :featured_slot, :integer
    field :discount, :integer, default: 0
    field :categorias, {:array, :string}, default: []
    field :pin_hash, :string
    field :pin_visto, :boolean, default: false
    belongs_to :user, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(brand, attrs) do
    brand
    |> cast(attrs, [:name, :logo, :cover_image, :description, :address, :address_full, :horario_atencion, :colores, :latitude, :longitude, :image_limit, :active, :modalidad, :featured_slot, :user_id, :discount, :categorias, :asistencia_activa, :asistencia_activada_en])
    |> validate_required([:user_id])
    |> validate_inclusion(:modalidad, ["presencial", "digital", "ambos"])
    |> validate_number(:discount, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:image_limit, [12, 14, 18, 22, 30])
  end

  def crear_pin_changeset(brand, pin) do
    hash = Bcrypt.hash_pwd_salt(pin)
    cast(brand, %{pin_hash: hash}, [:pin_hash])
  end

  def marcar_pin_visto_changeset(brand) do
    cast(brand, %{pin_visto: true}, [:pin_visto])
  end

  def pin_valido?(brand, pin) do
    Bcrypt.verify_pass(pin, brand.pin_hash || "")
  end
end

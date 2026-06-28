defmodule DaleApp.Mensajes.Mensaje do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mensajes" do
    field :texto, :string
    field :leido, :boolean, default: false
    belongs_to :remitente, DaleApp.Accounts.User
    belongs_to :destinatario, DaleApp.Accounts.User

    timestamps()
  end

  def changeset(mensaje, attrs) do
    mensaje
    |> cast(attrs, [:texto, :leido, :remitente_id, :destinatario_id])
    |> validate_required([:texto, :remitente_id, :destinatario_id])
    |> validate_length(:texto, min: 1, max: 2000)
  end
end

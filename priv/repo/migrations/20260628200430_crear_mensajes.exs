defmodule DaleApp.Repo.Migrations.CrearMensajes do
  use Ecto.Migration

  def change do
    create table(:mensajes) do
      add :remitente_id, references(:users, on_delete: :delete_all), null: false
      add :destinatario_id, references(:users, on_delete: :delete_all), null: false
      add :texto, :text, null: false
      add :leido, :boolean, default: false, null: false

      timestamps()
    end

    create index(:mensajes, [:remitente_id])
    create index(:mensajes, [:destinatario_id])
    create index(:mensajes, [:remitente_id, :destinatario_id])
  end
end

defmodule DaleApp.Repo.Migrations.AddExpiresAtToClaims do
  use Ecto.Migration

  def change do
    alter table(:claims) do
      add :expires_at, :utc_datetime
    end
  end
end

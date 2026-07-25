defmodule DaleApp.Repo.Migrations.RenameMicrosoftIdToDiscordId do
  use Ecto.Migration

  def change do
    drop unique_index(:users, [:microsoft_id])
    rename table(:users), :microsoft_id, to: :discord_id
    create unique_index(:users, [:discord_id])
  end
end

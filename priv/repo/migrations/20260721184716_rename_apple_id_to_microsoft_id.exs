defmodule DaleApp.Repo.Migrations.RenameAppleIdToMicrosoftId do
  use Ecto.Migration

  def change do
    drop unique_index(:users, [:apple_id])
    rename table(:users), :apple_id, to: :microsoft_id
    create unique_index(:users, [:microsoft_id])
  end
end

defmodule DaleApp.Repo.Migrations.AddTelefonoToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :telefono, :string
    end
  end
end

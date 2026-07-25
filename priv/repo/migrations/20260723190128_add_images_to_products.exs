defmodule DaleApp.Repo.Migrations.AddImagesToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :images, {:array, :string}, default: []
    end
  end
end

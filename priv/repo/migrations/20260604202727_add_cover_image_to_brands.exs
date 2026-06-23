defmodule DaleApp.Repo.Migrations.AddCoverImageToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :cover_image, :string
    end
  end
end

defmodule DaleApp.Repo.Migrations.AmpliarImagenUrl do
  use Ecto.Migration

  def change do
    alter table(:publicaciones) do
      modify :imagen_url, :text
    end
  end
end

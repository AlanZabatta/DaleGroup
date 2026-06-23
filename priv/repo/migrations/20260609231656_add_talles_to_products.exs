defmodule DaleApp.Repo.Migrations.AddTallesToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :talles, {:array, :string}, default: []
      modify :tipo, :string, null: true
    end
  end
end

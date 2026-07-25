defmodule DaleApp.Repo.Migrations.AddHorarioAtencionToBrands do
  use Ecto.Migration

  def change do
    alter table(:brands) do
      add :horario_atencion, :string
    end
  end
end

defmodule DaleApp.Repo.Migrations.CreateLogrosMensuales do
  use Ecto.Migration

  def change do
    # Congela el resultado de un ciclo de 30 dias, una vez calculado. No se
    # recalcula despues: si el dueno desempata, esa decision tiene que
    # sobrevivir aunque se vuelva a mirar el ciclo.
    create table(:logros_mensuales) do
      add :brand_id, references(:brands, on_delete: :delete_all), null: false
      add :ciclo_inicio, :date, null: false
      add :ciclo_fin, :date, null: false

      # Puntaje de logro de cada empleado ese ciclo: suma del bonus por
      # posicion en su propio podio de categoria + el bonus por posicion en
      # el podio de asistencia (comun a todos los roles). Escala 10/8/6/4.
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :puntos_logro, :integer, null: false, default: 0
      add :posicion_categoria, :integer
      add :posicion_asistencia, :integer

      # Si hay empate en el puntaje mas alto, todos los empatados ganan por
      # default. El dueno puede desempatar tocando a uno — eso se guarda aca
      # y ya no se vuelve a calcular solo.
      add :es_ganador, :boolean, null: false, default: false
      add :ganador_elegido_manualmente, :boolean, null: false, default: false

      timestamps()
    end

    create index(:logros_mensuales, [:brand_id, :ciclo_inicio])
    create unique_index(:logros_mensuales, [:brand_id, :ciclo_inicio, :user_id],
             name: :logros_mensuales_ciclo_usuario_unico
           )
  end
end

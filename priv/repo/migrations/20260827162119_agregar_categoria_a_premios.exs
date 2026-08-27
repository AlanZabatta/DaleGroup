defmodule DaleApp.Repo.Migrations.AgregarCategoriaAPremios do
  use Ecto.Migration

  def change do
    # Cada premio pertenece a UNA categoria. Ventas y Gestores tienen economias
    # separadas: sus puntos no se convierten entre si, asi que un premio no
    # puede tener un precio "equivalente" en la otra moneda. Si el dueno quiere
    # el mismo premio en ambas listas, lo carga dos veces con precios distintos.
    #
    # Default "ventas" para que los premios que ya existen queden asignados a
    # una lista en vez de desaparecer de todas.
    alter table(:premios) do
      add :categoria, :string, null: false, default: "ventas"
    end

    create index(:premios, [:brand_id, :categoria])
  end
end

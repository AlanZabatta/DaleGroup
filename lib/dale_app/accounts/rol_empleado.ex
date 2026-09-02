defmodule DaleApp.Accounts.RolEmpleado do
  @moduledoc """
  Los 4 roles de empleado: definen a la vez qué puede tocar en la app
  y en qué categoría de ranking compite (sistema de puntos y podios).

  Se guardan en el campo `zona` de `User` (reusado, ya existía como texto libre).
  """

  @roles %{
    "gerente" => %{nombre: "Gerente", categoria_ranking: "multitask"},
    "cajero" => %{nombre: "Cajero/a", categoria_ranking: "cajero"},
    "gestiones" => %{nombre: "Gestiones", categoria_ranking: "gestiones"},
    "multitask" => %{nombre: "MultiTask", categoria_ranking: "multitask"},
    "contador" => %{nombre: "Contador/a", categoria_ranking: nil}
  }

  @doc "Todos los roles, en orden fijo: Gerente, Cajero, Gestiones, MultiTask, Contador/a"
  def roles do
    [
      {"gerente", @roles["gerente"]},
      {"cajero", @roles["cajero"]},
      {"gestiones", @roles["gestiones"]},
      {"multitask", @roles["multitask"]},
      {"contador", @roles["contador"]}
    ]
  end

  def lista_codigos, do: Map.keys(@roles)

  def valido?(codigo), do: Map.has_key?(@roles, codigo)

  def nombre(codigo), do: get_in(@roles, [codigo, :nombre]) || "Sin rol"

  @doc "gerente y multitask comparten categoría de ranking (compiten como MultiTask)"
  def categoria_ranking(codigo), do: get_in(@roles, [codigo, :categoria_ranking])
end

defmodule DaleAppWeb.PushController do
  use DaleAppWeb, :controller
  alias DaleApp.Accounts

  def suscribir(conn, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Accounts.guardar_push_subscription(%{
             user_id: user_id,
             endpoint: endpoint,
             p256dh: p256dh,
             auth: auth
           }) do
        {:ok, _} -> json(conn, %{ok: true})
        {:error, _} -> json(conn, %{ok: false})
      end
    else
      json(conn, %{ok: false, error: "No autenticado"})
    end
  end

  def suscribir(conn, _params) do
    json(conn, %{ok: false, error: "Datos incompletos"})
  end

  def desuscribir(conn, %{"endpoint" => endpoint}) do
    Accounts.borrar_push_subscription(endpoint)
    json(conn, %{ok: true})
  end
end

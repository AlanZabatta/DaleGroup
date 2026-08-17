defmodule DaleAppWeb.GestoresLive do
  use DaleAppWeb, :live_view

  alias DaleApp.Repo
  alias DaleApp.Brands.Brand

  def mount(_params, session, socket) do
    user_id = session["user_id"]
    brand = if user_id, do: Repo.get_by(Brand, user_id: user_id), else: nil

    {:ok, assign(socket, brand: brand)}
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 24px 18px 40px; font-family: Poppins, sans-serif; max-width: 600px; margin: 0 auto; background-color: white; min-height: 100vh;">
      <.link navigate="/mi-tienda/cajeros" style="display: inline-flex; background: none; border: none; color: #186904; font-size: 22px; font-weight: 700; cursor: pointer; line-height: 1; text-decoration: none; margin-bottom: 16px;">&#x2715;</.link>
      <p style="font-size: 26px; font-weight: 800; color: #186904; margin: 0 0 20px;">Gestores</p>
    </div>
    """
  end
end

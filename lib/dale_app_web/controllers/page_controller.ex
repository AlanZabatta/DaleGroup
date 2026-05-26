defmodule DaleAppWeb.PageController do
  use DaleAppWeb, :controller

  alias DaleApp.Accounts

  def home(conn, _params) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: Accounts.get_user(user_id), else: nil
    render(conn, :home, current_user: current_user)
  end
end

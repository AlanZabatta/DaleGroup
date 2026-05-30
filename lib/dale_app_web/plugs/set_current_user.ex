defmodule DaleAppWeb.Plugs.SetCurrentUser do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    current_user = if user_id, do: DaleApp.Accounts.get_user(user_id), else: nil
    assign(conn, :current_user, current_user)
  end
end

defmodule DaleApp.Repo do
  use Ecto.Repo,
    otp_app: :dale_app,
    adapter: Ecto.Adapters.Postgres
end

defmodule DaleAppWeb.Router do
  use DaleAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DaleAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DaleAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/auth/google", AuthController, :request
    get "/auth/google/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :logout
    get "/admin", AdminController, :index
    post "/admin/:id/role", AdminController, :update_role
    post "/admin/:id/ban", AdminController, :ban
    post "/admin/brand/:id/disable", AdminController, :disable_brand
    get "/mi-tienda", BrandController, :mi_tienda
    post "/mi-tienda", BrandController, :update
    get "/mi-tienda/cupon", CouponController, :new
    post "/mi-tienda/cupon", CouponController, :create
    get "/mi-tienda/cajeros", BrandController, :cajeros
    post "/mi-tienda/cajeros/:id/remove", BrandController, :remove_cajero
    get "/marcas", MarcasController, :index
    get "/marcas/:id", MarcasController, :show
    post "/claims", ClaimController, :create
    get "/cajero/scanear", ClaimController, :redeem
    get "/unirse/:brand_id", BrandController, :unirse
  end

  if Application.compile_env(:dale_app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DaleAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

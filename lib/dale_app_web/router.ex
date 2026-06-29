defmodule DaleAppWeb.Router do
  use DaleAppWeb, :router
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DaleAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug DaleAppWeb.Plugs.SetCurrentUser
  end
  pipeline :api do
    plug :accepts, ["json"]
  end
  scope "/", DaleAppWeb do
    pipe_through :browser
    get "/", PageController, :home
    get "/productos", PageController, :productos
    get "/amigos", PageController, :amigos
    post "/amigos/buscar", FriendController, :buscar
    post "/perfil/username", PageController, :cambiar_username
    post "/perfil/foto", PageController, :cambiar_foto
    post "/perfil/config", PageController, :guardar_config
    post "/perfil/vitrina", PageController, :cambiar_vitrina
    post "/amigos/solicitar", FriendController, :solicitar
    post "/amigos/aceptar/:id", FriendController, :aceptar
    post "/amigos/rechazar/:id", FriendController, :rechazar
    get "/chat/:id", MensajeController, :chat
    post "/chat/:id/enviar", MensajeController, :enviar
    get "/chat/:id/listar", MensajeController, :listar
    post "/publicaciones/crear", PublicacionController, :crear
    post "/publicaciones/:publicacion_id/like", LikeController, :toggle
    delete "/publicaciones/:id", PublicacionController, :borrar
    post "/publicaciones/:publicacion_id/comentarios", ComentarioController, :crear
    get "/publicaciones/:publicacion_id/comentarios", ComentarioController, :listar
    post "/comentarios/:comentario_id/like", ComentarioLikeController, :toggle
    get "/tiendas", PageController, :tiendas
    get "/auth/google", AuthController, :request
    get "/auth/google/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :logout
    get "/admin", AdminController, :index
    get "/admin/stats", AdminController, :stats
    post "/admin/:id/role", AdminController, :update_role
    post "/admin/:id/ban", AdminController, :ban
    post "/admin/brand/:id/disable", AdminController, :disable_brand
    post "/admin/brand/:id/slot", AdminController, :assign_slot
    get "/mi-tienda", BrandController, :mi_tienda
    post "/mi-tienda", BrandController, :update
    get "/mi-stand", BrandController, :mi_stand
    get "/mi-tienda/cupon", CouponController, :new
    post "/mi-tienda/cupon", CouponController, :create
    get "/mi-tienda/cajeros", BrandController, :cajeros
    get "/mi-tienda/productos", ProductoController, :index
    post "/mi-tienda/productos/crear", ProductoController, :crear
    delete "/mi-tienda/productos/:id", ProductoController, :borrar
    post "/mi-tienda/cajeros/:id/remove", BrandController, :remove_cajero
    get "/marcas", MarcasController, :index
    get "/marcas/:id", MarcasController, :show
    post "/claims", ClaimController, :create
    get "/cajero/scanear", ClaimController, :redeem
    get "/unirse/:brand_id", BrandController, :unirse
    get "/catalogo", PageController, :home
    get "/categorias", PageController, :home
    get "/beneficios", PageController, :home
    get "/mis-puntos", PageController, :home
    get "/nosotros", PageController, :home
    get "/terminos", PageController, :home
    get "/contacto", PageController, :home
    get "/ayuda", PageController, :home
    get "/mis-cupones", PageController, :home
    get "/mapa", PageController, :mapa
    get "/perfil", PageController, :perfil
    post "/productos/:id/imagen", ProductoController, :upload_imagen
    post "/marcas/:id/logo", BrandController, :upload_logo
    post "/marcas/:id/cover", BrandController, :upload_cover
    post "/productos/:id/nombre", ProductoController, :update_nombre
    post "/mapa/agregar/:brand_id", MapaController, :agregar
    delete "/mapa/quitar/:brand_id", MapaController, :quitar
    get "/favoritos", FavoritoController, :index
    post "/favoritos/:product_id", FavoritoController, :toggle
    get "/productos/:id/detalle", ProductoController, :detalle
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

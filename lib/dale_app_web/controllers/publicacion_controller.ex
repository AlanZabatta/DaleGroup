defmodule DaleAppWeb.PublicacionController do
  use DaleAppWeb, :controller
  alias DaleApp.Publicaciones
  alias DaleApp.Storage

  def crear(conn, %{"imagenes" => imagenes, "descripcion" => descripcion}) do
    user = conn.assigns.current_user
    unless user, do: json(conn, %{ok: false, error: "no_auth"})
    imagenes = if is_list(imagenes), do: imagenes, else: [imagenes]
    imagenes = Enum.reject(imagenes, &is_nil/1)
    imagenes = Enum.take(imagenes, 4)
    urls = Enum.map(imagenes, fn imagen ->
      case Storage.upload_image(imagen.path, imagen.filename) do
        {:ok, %{body: body}} when is_map(body) -> body["secure_url"]
        _ -> nil
      end
    end) |> Enum.reject(&is_nil/1)
    if urls == [] do
      json(conn, %{ok: false, error: "error al subir imagenes"})
    else
      case Publicaciones.crear(%{
        user_id: user.id,
        imagen_url: Enum.join(urls, ","),
        descripcion: descripcion
      }) do
        {:ok, _pub} -> json(conn, %{ok: true})
        {:error, changeset} -> json(conn, %{ok: false, error: inspect(changeset.errors)})
      end
    end
  end

  def borrar(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    unless user && user.role == "admin", do: json(conn, %{ok: false, error: "no autorizado"})
    case DaleApp.Repo.get(DaleApp.Publicaciones.Publicacion, id) do
      nil -> json(conn, %{ok: false, error: "no existe"})
      pub ->
        DaleApp.Repo.delete(pub)
        json(conn, %{ok: true})
    end
  end
end

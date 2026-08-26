defmodule DaleApp.Storage do
  alias ExAws.S3

  defp r2_config do
    [
      access_key_id: System.get_env("CLOUDFLARE_R2_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("CLOUDFLARE_R2_SECRET_ACCESS_KEY"),
      region: "auto",
      host: "#{System.get_env("CLOUDFLARE_R2_ACCOUNT_ID")}.r2.cloudflarestorage.com",
      scheme: "https://"
    ]
  end

  defp bucket, do: System.get_env("CLOUDFLARE_R2_BUCKET")
  defp public_url, do: System.get_env("CLOUDFLARE_R2_PUBLIC_URL")

  def upload_image(file_path, filename) do
    upload_image(file_path, filename, [])
  end

  # extra_params (usados antes para transformaciones de Cloudinary como recorte)
  # se ignoran acá: R2 no hace transformaciones server-side. El recorte real ya
  # se hace client-side con Cropper.js antes de subir, así que no debería notarse.
  def upload_image(file_path, filename, _extra_params) do
    ext = filename |> Path.extname() |> String.downcase()
    ext = if ext in [".png", ".webp", ".jpg", ".jpeg"], do: ext, else: ".jpg"
    key = "#{Ecto.UUID.generate()}#{ext}"

    mime =
      cond do
        ext == ".png" -> "image/png"
        ext == ".webp" -> "image/webp"
        true -> "image/jpeg"
      end

    file_content = File.read!(file_path)

    S3.put_object(bucket(), key, file_content, content_type: mime)
    |> ExAws.request(r2_config())
    |> case do
      {:ok, %{status_code: 200}} ->
        url = "#{public_url()}/#{key}"
        {:ok, %{status: 200, body: %{"secure_url" => url}}}

      {:ok, %{status_code: status}} ->
        {:error, %{status: status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_image(url_o_key) do
    key = extraer_key(url_o_key)

    S3.delete_object(bucket(), key)
    |> ExAws.request(r2_config())
    |> case do
      {:ok, resultado} -> {:ok, resultado}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extraer_key(url) do
    base = public_url()

    if base && String.starts_with?(url, base) do
      url |> String.replace_prefix(base, "") |> String.trim_leading("/")
    else
      url |> String.split("/") |> List.last()
    end
  end
end

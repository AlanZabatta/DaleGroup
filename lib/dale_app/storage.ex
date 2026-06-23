defmodule DaleApp.Storage do
  def upload_image(file_path, filename) do
    upload_image(file_path, filename, [])
  end

  def upload_image(file_path, filename, extra_params) do
    cloud_name = System.get_env("CLOUDINARY_CLOUD_NAME")
    api_key = System.get_env("CLOUDINARY_API_KEY")
    api_secret = System.get_env("CLOUDINARY_API_SECRET")

    timestamp = System.os_time(:second) |> to_string()
    signature_string = "timestamp=#{timestamp}#{api_secret}"
    signature = :crypto.hash(:sha, signature_string) |> Base.encode16(case: :lower)

    file_content = File.read!(file_path)
    base64 = Base.encode64(file_content)

    mime = cond do
      String.ends_with?(filename, ".png") -> "image/png"
      String.ends_with?(filename, ".webp") -> "image/webp"
      true -> "image/jpeg"
    end

    data_uri = "data:#{mime};base64,#{base64}"

    url = "https://api.cloudinary.com/v1_1/#{cloud_name}/image/upload"

    form_params = [
      file: data_uri,
      api_key: api_key,
      timestamp: timestamp,
      signature: signature
    ] ++ Enum.map(extra_params, fn {k, v} -> {String.to_atom(to_string(k)), to_string(v)} end)

    Req.post(url, form: form_params)
  end

  def delete_image(public_id) do
    cloud_name = System.get_env("CLOUDINARY_CLOUD_NAME")
    api_key = System.get_env("CLOUDINARY_API_KEY")
    api_secret = System.get_env("CLOUDINARY_API_SECRET")
    timestamp = System.os_time(:second) |> to_string()
    signature_string = "public_id=#{public_id}&timestamp=#{timestamp}#{api_secret}"
    signature = :crypto.hash(:sha, signature_string) |> Base.encode16(case: :lower)
    url = "https://api.cloudinary.com/v1_1/#{cloud_name}/image/destroy"
    Req.post(url, form: [public_id: public_id, api_key: api_key, timestamp: timestamp, signature: signature])
  end
end
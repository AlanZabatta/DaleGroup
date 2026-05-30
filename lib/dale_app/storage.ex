defmodule DaleApp.Storage do
  def upload_image(file_path, _filename) do
    cloud_name = System.get_env("CLOUDINARY_CLOUD_NAME")
    api_key = System.get_env("CLOUDINARY_API_KEY")
    api_secret = System.get_env("CLOUDINARY_API_SECRET")

    timestamp = System.os_time(:second) |> to_string()
    signature_string = "timestamp=#{timestamp}#{api_secret}"
    signature = :crypto.hash(:sha, signature_string) |> Base.encode16(case: :lower)

    file_content = File.read!(file_path)
    base64 = Base.encode64(file_content)
    data_uri = "data:image/jpeg;base64,#{base64}"

    url = "https://api.cloudinary.com/v1_1/#{cloud_name}/image/upload"

    Req.post(url,
      form: [
        file: data_uri,
        api_key: api_key,
        timestamp: timestamp,
        signature: signature
      ]
    )
  end
end

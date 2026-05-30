defmodule DaleApp.Cloudflare do
  def upload_image(file_path, filename) do
    account_id = System.get_env("CLOUDFLARE_ACCOUNT_ID")
    api_token = System.get_env("CLOUDFLARE_API_TOKEN")

    url = "https://api.cloudflare.com/client/v4/accounts/#{account_id}/images/v1"

    Req.post(url,
      headers: [{"Authorization", "Bearer #{api_token}"}],
      form_multipart: [
        file: {File.read!(file_path), filename: filename, content_type: "image/jpeg"}
      ]
    )
  end
end

defmodule DaleApp.Cloudflare do
  def upload_image(image_data, filename) do
    account_id = Application.get_env(:dale_app, :cloudflare)[:account_id]
    api_token = Application.get_env(:dale_app, :cloudflare)[:api_token]

    url = "https://api.cloudflare.com/client/v4/accounts/#{account_id}/images/v1"

    Req.post(url,
      headers: [{"Authorization", "Bearer #{api_token}"}],
      form_multipart: [
        file: {image_data, filename: filename, content_type: "image/jpeg"}
      ]
    )
  end
end

defmodule DaleApp.ExAwsReqHttpClient do
  @moduledoc """
  Adaptador para que ex_aws use Req (ya instalado en el proyecto) como
  motor HTTP, en vez de hackney (que arrastra una dependencia vieja,
  parse_trans, incompatible con versiones nuevas de Erlang/OTP).
  """
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body \\ "", headers \\ [], _http_opts \\ []) do
    case Req.request(
           method: method,
           url: url,
           body: body,
           headers: headers,
           retry: false,
           decode_body: false
         ) do
      {:ok, %Req.Response{status: status, body: resp_body, headers: resp_headers}} ->
        {:ok, %{status_code: status, body: resp_body, headers: resp_headers}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end

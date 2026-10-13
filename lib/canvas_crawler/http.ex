# lib/canvas_crawler/http.ex
defmodule CanvasCrawler.HTTP do
  @moduledoc """
  Minimal HTTPS GET over Erlang's :httpc with certificate verification.
  """

  @timeout :timer.seconds(20)

  @doc """
  Returns `{:ok, headers, body}` for 2xx, `{:error, {:auth_expired, status}}`
  for 401/302, or `{:error, reason}` otherwise.
  """
  def get(url, extra_headers \\ []) do
    headers =
      [
        # Canvas's WAF rejects requests with no User-Agent (403); :httpc sends none by default.
        {~c"user-agent", ~c"canvas_crawler/0.1 (Elixir)"}
        | Enum.map(extra_headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
      ]

    http_opts = [
      timeout: @timeout,
      connect_timeout: @timeout,
      # Canvas answers an expired session with a redirect to the login page.
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, resp_headers, body}} when status in 200..299 ->
        {:ok, resp_headers, body}

      {:ok, {{_, status, _}, _, _}} when status in [401, 302] ->
        {:error, {:auth_expired, status}}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, {:network, reason}}
    end
  end
end

# lib/canvas_crawler/application.ex
defmodule CanvasCrawler.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CanvasCrawler.Server
    ]

    opts = [strategy: :one_for_one, name: CanvasCrawler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

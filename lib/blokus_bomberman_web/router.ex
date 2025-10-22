defmodule BlokusBombermanWeb.Router do
  use BlokusBombermanWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlokusBombermanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BlokusBombermanWeb do
    pipe_through :browser

    live "/", GameLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", BlokusBombermanWeb do
  #   pipe_through :api
  # end
end

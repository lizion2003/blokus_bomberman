defmodule BlokusBombermanWeb.PageController do
  use BlokusBombermanWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

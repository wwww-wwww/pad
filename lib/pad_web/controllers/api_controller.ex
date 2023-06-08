defmodule PadWeb.ApiController do
  use PadWeb, :controller

  def diff(conn, %{"file" => file}) do
    if File.exists?("diff/#{file}") do
      conn
      |> send_file(200, "diff/#{file}")
    else
      conn
      |> send_resp(404, "File not found.")
    end
  end

  def songinfo(conn, %{"file" => file}) do
    if File.exists?("songinfo/#{file}") do
      conn
      |> send_file(200, "songinfo/#{file}")
    else
      conn
      |> send_resp(404, "File not found.")
    end
  end

  def list_pads(conn, _params) do
    json(conn, Pad.Songlist.get_all_pads() |> Enum.map(&elem(&1, 0)))
  end
end

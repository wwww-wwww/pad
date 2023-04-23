defmodule Pad do
  @moduledoc """
  Pad keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def regen_pass() do
    password = Bcrypt.gen_salt()
    Application.put_env(:pad, :superdelete, Bcrypt.hash_pwd_salt(password))
    password
  end

  def check_password(password) do
    case Application.get_env(:pad, :superdelete) do
      nil -> false
      key -> Bcrypt.verify_pass(password, key)
    end
  end
end

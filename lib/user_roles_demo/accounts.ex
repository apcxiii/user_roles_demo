defmodule UserRolesDemo.Accounts do
  @moduledoc """
  Accounts modules with crud operations.
  """
  import Ecto.Query, warn: false

  alias UserRolesDemo.Accounts.{Role, User, UserNotifier}
  alias UserRolesDemo.Repo
  alias UserRolesDemoWeb.Endpoint

  @pubsub UserRolesDemo.PubSub
  @topic "users"

  # sal de firma del token: cambia esto si algún día quieres invalidar
  # todos los tokens existentes de golpe (ej. tras una brecha de seguridad)
  @token_salt "user auth"
  # 7 días
  @token_max_age_seconds 60 * 60 * 24 * 7

  @reset_password_salt "reset password"
  # 20 minutos — el usuario siempre puede pedir un link nuevo.
  @reset_password_token_max_age_seconds 60 * 20

  ## Roles — CRUD con borrado lógico

  def list_roles(opts \\ []) do
    Role
    |> maybe_filter_active(opts)
    |> Repo.all()
  end

  defp maybe_filter_active(query, opts) do
    if Keyword.get(opts, :include_inactive, false) do
      query
    else
      where(query, [r], not is_nil(r.active))
    end
  end

  def get_role!(id), do: Repo.get!(Role, id)

  def create_role(attrs) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  def update_role(%Role{} = role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  # "Eliminar" lógico: no borra la fila, apaga el flag `active`
  def soft_delete_role(%Role{} = role) do
    update_role(role, %{active: false})
  end

  def restore_role(%Role{} = role) do
    update_role(role, %{active: true})
  end

  ## Usuarios — listado, con broadcast por PubSub

  def list_users do
    User
    |> preload(:roles)
    |> Repo.all()
  end

  def get_user!(id) do
    User
    |> preload(:roles)
    |> Repo.get!(id)
  end

  def get_user_by_email(email) when is_binary(email) do
    User
    |> preload(:roles)
    |> Repo.get_by(email: email)
  end

  def create_user(attrs, role_ids \\ []) do
    %User{}
    |> User.changeset(attrs, roles_from_ids(role_ids))
    |> Repo.insert()
    |> broadcast(:user_created)
  end

  def update_user(%User{} = user, attrs, role_ids \\ nil) do
    user
    |> User.changeset(attrs, role_ids && roles_from_ids(role_ids))
    |> Repo.update()
    |> broadcast(:user_updated)
  end

  def delete_user(%User{} = user) do
    user
    |> Repo.delete()
    |> broadcast(:user_deleted)
  end

  defp roles_from_ids([]), do: []
  defp roles_from_ids(ids), do: Repo.all(from r in Role, where: r.id in ^ids)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  El password es opcional aquí: dejarlo en blanco conserva el actual;
  si se escribe uno nuevo, se valida pero no se hashea todavía
  (`hash_password: false`) para no recalcular bcrypt en cada validación.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs, nil, hash_password: false)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes
  (incluye `:password`, sin recalcular el hash bcrypt en cada validación).

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, nil, hash_password: false)
  end

  ## PubSub

  def subscribe_users, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  defp broadcast({:ok, record}, event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, record})
    {:ok, record}
  end

  defp broadcast(error, _event), do: error

  @doc """
  Deletes a role.

  ## Examples

      iex> delete_role(role)
      {:ok, %Role{}}

      iex> delete_role(role)
      {:error, %Ecto.Changeset{}}

  """
  def delete_role(%Role{} = role) do
    Repo.delete(role)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking role changes.

  ## Examples

      iex> change_role(role)
      %Ecto.Changeset{data: %Role{}}

  """
  def change_role(%Role{} = role, attrs \\ %{}) do
    Role.changeset(role, attrs)
  end

  ## Registro + autenticación

  def register_user(attrs, role_ids \\ []) do
    %User{}
    |> User.registration_changeset(attrs, roles_from_ids(role_ids))
    |> Repo.insert()
  end

  @doc """
  Verifica email + password. Ejecuta un hash "dummy" cuando el email
  no existe para no filtrar por timing si el usuario es válido o no.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    cond do
      # un usuario inactivo responde igual que credenciales inválidas, para
      # no revelar que la cuenta existe.
      user && Bcrypt.verify_pass(password, user.hashed_password) && user.is_active ->
        {:ok, Repo.preload(user, :roles)}

      user ->
        {:error, :unauthorized}

      true ->
        Bcrypt.no_user_verify()
        {:error, :unauthorized}
    end
  end

  ## Tokens firmados (stateless) — mismo formato para sesión web y API Bearer

  def generate_user_token(%User{} = user) do
    Phoenix.Token.sign(Endpoint, @token_salt, user.id)
  end

  def fetch_user_by_token(token) when is_binary(token) do
    with {:ok, user_id} <-
           Phoenix.Token.verify(Endpoint, @token_salt, token, max_age: @token_max_age_seconds),
         # desactivar un usuario invalida de inmediato sus tokens/sesiones vigentes
         %User{is_active: true} = user <- Repo.get(User, user_id) do
      {:ok, Repo.preload(user, :roles)}
    else
      nil -> {:error, :invalid_token}
      %User{is_active: false} -> {:error, :invalid_token}
      {:error, _reason} = error -> error
    end
  end

  def fetch_user_by_token(_), do: {:error, :invalid_token}

  ## Reset de password ("olvidé mi contraseña")
  #
  # No usamos una tabla de tokens (a diferencia de `mix phx.gen.auth`): el
  # token es un `Phoenix.Token` firmado cuyo payload incluye un hash corto
  # (`:erlang.phash2/1`) del `hashed_password` vigente al momento de emitirlo.
  # Al verificar, se recalcula ese hash sobre el `hashed_password` actual del
  # usuario — si no coincide (porque la contraseña ya cambió, sea por este
  # mismo reset o por otro), el token se rechaza. Así cualquier link emitido
  # queda invalidado en el momento en que se usa, sin necesidad de guardar ni
  # borrar nada en la base de datos.

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking a password reset (sin recalcular
  el hash bcrypt en cada validación en vivo).
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Sets a new password for `user`, hasheándola antes de persistir.
  """
  def reset_user_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Generates a token for `user` that `fetch_user_by_reset_password_token/1`
  can later verify. Expira en #{div(@reset_password_token_max_age_seconds, 60)}
  minutos, o antes si la contraseña del usuario ya cambió.
  """
  def generate_user_reset_password_token(%User{} = user) do
    payload = %{id: user.id, hash: :erlang.phash2(user.hashed_password)}
    Phoenix.Token.sign(Endpoint, @reset_password_salt, payload)
  end

  @doc """
  Verifies a reset-password token and returns the matching user, as long as
  it hasn't expired and the password hasn't changed since it was issued.
  """
  def fetch_user_by_reset_password_token(token) when is_binary(token) do
    with {:ok, %{id: id, hash: hash}} <-
           Phoenix.Token.verify(Endpoint, @reset_password_salt, token,
             max_age: @reset_password_token_max_age_seconds
           ),
         %User{} = user <- Repo.get(User, id),
         true <- :erlang.phash2(user.hashed_password) == hash do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def fetch_user_by_reset_password_token(_), do: {:error, :invalid_token}

  @doc """
  Delivers the reset-password email to `user`, building the URL with
  `reset_password_url_fun` (keeps this context decoupled from the router).

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset-password/\#{&1}"))
      {:ok, %Swoosh.Email{}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    token = generate_user_reset_password_token(user)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(token))
  end
end

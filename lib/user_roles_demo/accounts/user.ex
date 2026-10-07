defmodule UserRolesDemo.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :is_active, :boolean, default: true
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true

    many_to_many :roles, UserRolesDemo.Accounts.Role,
      join_through: "users_roles",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  # edición: el password es opcional — en blanco significa "no cambiarlo".
  def changeset(user, attrs, roles \\ nil, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :is_active])
    |> validate_required([:name, :email, :is_active])
    |> maybe_validate_password()
    |> unique_constraint(:email)
    |> maybe_put_roles(roles)
    |> maybe_hash_password(opts)
  end

  defp maybe_validate_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      "" -> delete_change(changeset, :password)
      _ -> validate_length(changeset, :password, min: 8, max: 72)
    end
  end

  # registro: valida y hashea la contraseña.
  # `hash_password: false` se usa en las validaciones "en vivo" (phx-change)
  # para no recalcular el hash bcrypt (deliberadamente lento) en cada tecla.
  def registration_changeset(user, attrs, roles \\ nil, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :password, :is_active])
    |> validate_required([:name, :email, :password, :is_active])
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> maybe_put_roles(roles)
    |> maybe_hash_password(opts)
  end

  # reseteo de password ("olvidé mi contraseña"): solo pide/valida el password,
  # sin tocar name/email/roles.
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(password))
    else
      changeset
    end
  end

  defp maybe_put_roles(changeset, nil), do: changeset
  defp maybe_put_roles(changeset, roles), do: put_assoc(changeset, :roles, roles)
end

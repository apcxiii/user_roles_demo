# Guía: Proyecto Phoenix LiveView + Ecto — Usuarios con Roles (borrado lógico) + PubSub

## 0. Qué vamos a construir

- Proyecto Phoenix nuevo con LiveView + Ecto (Postgres).
- `User` *has many* `Role` (relación `many_to_many` vía tabla intermedia `users_roles`).
- CRUD de **Roles** (crear, editar, eliminar) con **borrado lógico**: una columna `active` (boolean) en lugar de `DELETE` físico.
- Listado principal de **Usuarios** con **Phoenix.PubSub**: cuando alguien crea/edita/elimina un usuario en una pestaña, todas las demás pestañas conectadas se actualizan en vivo.
- **Autenticación con password + token firmado**: login web por sesión y el mismo token reutilizable como `Authorization: Bearer` si más adelante expones una API JSON.
- Repo en GitHub + pipeline de **CI** (tests con Postgres en GitHub Actions) y, opcionalmente, **CD** (deploy automático en tu propia Mac, con un self-hosted runner y `mix release`, tras pasar CI).

---

## 1. Instalar asdf en macOS (Apple Silicon / M1)

### 1.1 Diagnóstico rápido

```bash
uname -m          # debe decir: arm64
which brew        # debe ser /opt/homebrew/bin/brew (NO /usr/local/bin/brew)
file $(which brew) # confirma que el binario es arm64
```

Si `brew` está en `/usr/local/bin`, es la instalación Intel corriendo bajo Rosetta — no es lo ideal para M1. La instalación nativa vive en `/opt/homebrew`.

### 1.2 Quitar cualquier `asdf` roto y reinstalar vía Homebrew

```bash
# quita instalaciones previas conflictivas (binario, shims, config)
brew uninstall asdf 2>/dev/null
rm -rf ~/.asdf
sudo rm -f /usr/local/bin/asdf

# instala asdf nativo arm64 (versión Go, sin dependencias de bash)
arch -arm64 brew install asdf
```

### 1.3 Configurar el shell (zsh, default en macOS)

```bash
cat <<'EOF' >> ~/.zshrc

# --- asdf ---
export PATH="$(brew --prefix asdf)/bin:$PATH"
export PATH="$HOME/.asdf/shims:$PATH"
EOF

source ~/.zshrc
asdf version    # debe imprimir la versión sin error de "bad CPU type"
```

### 1.4 Dependencias nativas para compilar Erlang en ARM

```bash
arch -arm64 brew install autoconf openssl@3 wxwidgets libxslt fop unixodbc
```

> `wxwidgets` habilita `:observer`/`:debugger` (opcional pero útil). `libxslt`/`fop` son para generar documentación de Erlang — si no te interesa, puedes omitir el build de docs (ver más abajo, más rápido).

---

## 2. Instalar Erlang y Elixir vía asdf (optimizado para M1)

### 2.1 Plugins

```bash
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
```

### 2.2 Variables de entorno para acelerar/optimizar el build en Apple Silicon

Erlang/OTP ≥ 24 trae **JIT nativo para aarch64**, así que no necesitas flags especiales para activarlo — se detecta solo. Lo que sí conviene es **saltar la generación de documentación** (la parte más lenta del build) y apuntar a OpenSSL nativo arm64:

```bash
export KERL_BUILD_DOCS=no
export KERL_CONFIGURE_OPTIONS="--with-ssl=$(brew --prefix openssl@3) --enable-jit"
export CFLAGS="-O2 -march=native"
```

Puedes añadir estas 3 líneas a tu `~/.zshrc` si vas a compilar varias versiones seguido.

### 2.3 Instalar versiones (LTS actuales, buena combinación)

```bash
asdf install erlang 27.1.2
asdf install elixir 1.17.3-otp-27
```

> El build de Erlang tarda ~4-8 min en un M1 con `KERL_BUILD_DOCS=no`. Si falla, corre `asdf install erlang 27.1.2 -v` para ver el log completo — casi siempre es por falta de `openssl@3` en el PATH de compilación.

### 2.4 Fijar versiones globales o por proyecto

```bash
# global (todo tu usuario)
asdf global erlang 27.1.2
asdf global elixir 1.17.3-otp-27

# verifica
erl -eval 'erlang:display(erlang:system_info(emu_flavor)), halt().' -noshell
# debe imprimir: jit
elixir --version
```

Más adelante, en la carpeta del proyecto, generaremos un `.tool-versions` para fijarlo *por proyecto* (paso 3.1).

### 2.5 Hex y Phoenix

```bash
mix local.hex --force
mix local.rebar --force
mix archive.install hex phx_new --force
```

---

## 3. Crear el proyecto Phoenix LiveView + Ecto

### 3.1 Generar el proyecto

```bash
mix phx.new user_roles_demo --live
cd user_roles_demo

# fija las versiones de este proyecto (asdf las respeta al entrar a esta carpeta)
cat <<'EOF' > .tool-versions
erlang 27.1.2
elixir 1.17.3-otp-27
EOF
```

### 3.2 Base de datos (Postgres nativo arm64)

```bash
arch -arm64 brew install postgresql@16
brew services start postgresql@16
```

Ajusta `config/dev.exs` si tu usuario/host de Postgres no son los default (`postgres`/`postgres`@`localhost`).

```bash
mix ecto.create
```

---

## 4. Modelo de datos: `User` con muchos `Role` (many_to_many) + borrado lógico

### 4.1 Migraciones

```bash
mix ecto.gen.migration create_roles
mix ecto.gen.migration create_users
mix ecto.gen.migration create_users_roles
```

**`priv/repo/migrations/..._create_roles.exs`**

```elixir
defmodule UserRolesDemo.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :name, :string, null: false
      add :description, :string
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:name])
    create index(:roles, [:active])
  end
end
```

**`priv/repo/migrations/..._create_users.exs`**

```elixir
defmodule UserRolesDemo.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
  end
end
```

**`priv/repo/migrations/..._create_users_roles.exs`**

```elixir
defmodule UserRolesDemo.Repo.Migrations.CreateUsersRoles do
  use Ecto.Migration

  def change do
    create table(:users_roles, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role_id, references(:roles, on_delete: :delete_all), null: false
    end

    create unique_index(:users_roles, [:user_id, :role_id])
  end
end
```

```bash
mix ecto.migrate
```

### 4.2 Schemas

**`lib/user_roles_demo/accounts/role.ex`**

```elixir
defmodule UserRolesDemo.Accounts.Role do
  use Ecto.Schema
  import Ecto.Changeset

  schema "roles" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    many_to_many :users, UserRolesDemo.Accounts.User, join_through: "users_roles"

    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :active])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
```

**`lib/user_roles_demo/accounts/user.ex`**

```elixir
defmodule UserRolesDemo.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string

    many_to_many :roles, UserRolesDemo.Accounts.Role,
      join_through: "users_roles",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs, roles \\ nil) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
    |> unique_constraint(:email)
    |> maybe_put_roles(roles)
  end

  defp maybe_put_roles(changeset, nil), do: changeset
  defp maybe_put_roles(changeset, roles), do: put_assoc(changeset, :roles, roles)
end
```

### 4.3 Contexto `Accounts` — roles con borrado lógico + PubSub en usuarios

**`lib/user_roles_demo/accounts.ex`**

```elixir
defmodule UserRolesDemo.Accounts do
  import Ecto.Query, warn: false
  alias UserRolesDemo.Repo
  alias UserRolesDemo.Accounts.{User, Role}

  @pubsub UserRolesDemo.PubSub
  @topic "users"

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
      where(query, [r], r.active == true)
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

  ## PubSub

  def subscribe_users, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  defp broadcast({:ok, record}, event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, record})
    {:ok, record}
  end

  defp broadcast(error, _event), do: error
end
```

---

## 5. LiveViews

### 5.1 Roles — CRUD con borrado lógico (genera boilerplate y luego ajustamos)

```bash
mix phx.gen.live Accounts Role roles name:string description:string active:boolean
```

El generador crea `RoleLive.Index/Show/Form` y agrega rutas en el router (paso 5.3).

**Cada LiveView trae su plantilla en un archivo `.html.heex` colocado** (mismo nombre, mismo directorio) en lugar de un `render/1` con `~H"""..."""` embebido en el módulo:

```
lib/user_roles_demo_web/live/role_live/
├── index.ex          # sin render/1
├── index.html.heex
├── show.ex            # sin render/1
├── show.html.heex
├── form.ex            # sin render/1
└── form.html.heex
```

Phoenix LiveView usa automáticamente ese archivo cuando el módulo no define `render/1` — no hace falta configurar nada extra. Si partes de un `render/1` inline (por ejemplo si escribiste el LiveView a mano en vez de con el generador), muévelo así:

1. Copia el contenido entre `~H"""` y `"""` a un archivo nuevo `<nombre>.html.heex` junto al `.ex`.
2. Borra la función `render/1` completa del módulo.
3. Recompila (`mix compile`) — si Phoenix no encuentra la plantilla te avisa con un error claro.

Edita `lib/user_roles_demo_web/live/role_live/index.ex`:

- Cambia `Accounts.list_roles()` → ya filtra solo activos por default (nuestra función del paso 4.3).
- Cambia el `handle_event("delete", ...)` generado (que hace `Repo.delete`) por el soft delete:

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  role = Accounts.get_role!(id)
  {:ok, _} = Accounts.soft_delete_role(role)

  {:noreply, stream_delete(socket, :roles, role)}
end
```

Así el rol nunca se borra físicamente: solo desaparece del listado porque `list_roles/0` filtra `active == true`.

Con el ajuste anterior, así quedan los tres módulos y sus plantillas colocated:

**`lib/user_roles_demo_web/live/role_live/index.ex`**

```elixir
defmodule UserRolesDemoWeb.RoleLive.Index do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Roles")
     |> stream(:roles, list_roles())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    role = Accounts.get_role!(id)
    {:ok, _} = Accounts.soft_delete_role(role)

    {:noreply, stream_delete(socket, :roles, role)}
  end

  defp list_roles() do
    Accounts.list_roles()
  end
end
```

**`lib/user_roles_demo_web/live/role_live/index.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    Listing Roles
    <:actions>
      <.button variant="primary" navigate={~p"/roles/new"}>
        <.icon name="hero-plus" /> New Role
      </.button>
    </:actions>
  </.header>

  <.table
    id="roles"
    rows={@streams.roles}
    row_click={fn {_id, role} -> JS.navigate(~p"/roles/#{role}") end}
  >
    <:col :let={{_id, role}} label="Name">{role.name}</:col>
    <:col :let={{_id, role}} label="Description">{role.description}</:col>
    <:col :let={{_id, role}} label="Active">{role.active}</:col>
    <:action :let={{_id, role}}>
      <div class="sr-only">
        <.link navigate={~p"/roles/#{role}"}>Show</.link>
      </div>
      <.link navigate={~p"/roles/#{role}/edit"}>Edit</.link>
    </:action>
    <:action :let={{id, role}}>
      <.link
        phx-click={JS.push("delete", value: %{id: role.id}) |> hide("##{id}")}
        data-confirm="Are you sure?"
      >
        Delete
      </.link>
    </:action>
  </.table>
</Layouts.app>
```

> El click en la fila (`row_click`) ya navega al detalle, por eso el link "Show" queda oculto (`sr-only`, solo para lectores de pantalla) y las acciones visibles son "Edit" y "Delete". El botón "Delete" dispara el `handle_event("delete", ...)` de arriba vía `JS.push` y oculta la fila del stream con `hide("##{id}")` sin esperar la respuesta del servidor.

**`lib/user_roles_demo_web/live/role_live/show.ex`**

```elixir
defmodule UserRolesDemoWeb.RoleLive.Show do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Role")
     |> assign(:role, Accounts.get_role!(id))}
  end
end
```

**`lib/user_roles_demo_web/live/role_live/show.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    Role {@role.id}
    <:subtitle>This is a role record from your database.</:subtitle>
    <:actions>
      <.button navigate={~p"/roles"}>
        <.icon name="hero-arrow-left" />
      </.button>
      <.button variant="primary" navigate={~p"/roles/#{@role}/edit?return_to=show"}>
        <.icon name="hero-pencil-square" /> Edit role
      </.button>
    </:actions>
  </.header>

  <.list>
    <:item title="Name">{@role.name}</:item>
    <:item title="Description">{@role.description}</:item>
    <:item title="Active">{@role.active}</:item>
  </.list>
</Layouts.app>
```

> El botón "Edit role" navega con `?return_to=show`, así el `RoleLive.Form` sabe que al guardar debe regresar aquí (`show`) en vez de al listado (`index`) — ver `return_to/1` y `return_path/2` en el módulo `Form` de abajo.

**`lib/user_roles_demo_web/live/role_live/form.ex`**

```elixir
defmodule UserRolesDemoWeb.RoleLive.Form do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts
  alias UserRolesDemo.Accounts.Role

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    role = Accounts.get_role!(id)

    socket
    |> assign(:page_title, "Edit Role")
    |> assign(:role, role)
    |> assign(:form, to_form(Accounts.change_role(role)))
  end

  defp apply_action(socket, :new, _params) do
    role = %Role{}

    socket
    |> assign(:page_title, "New Role")
    |> assign(:role, role)
    |> assign(:form, to_form(Accounts.change_role(role)))
  end

  @impl true
  def handle_event("validate", %{"role" => role_params}, socket) do
    changeset = Accounts.change_role(socket.assigns.role, role_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"role" => role_params}, socket) do
    save_role(socket, socket.assigns.live_action, role_params)
  end

  defp save_role(socket, :edit, role_params) do
    case Accounts.update_role(socket.assigns.role, role_params) do
      {:ok, role} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, role))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_role(socket, :new, role_params) do
    case Accounts.create_role(role_params) do
      {:ok, role} ->
        {:noreply,
         socket
         |> put_flash(:info, "Role created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, role))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _role), do: ~p"/roles"
  defp return_path("show", role), do: ~p"/roles/#{role}"
end
```

**`lib/user_roles_demo_web/live/role_live/form.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    {@page_title}
    <:subtitle>Use this form to manage role records in your database.</:subtitle>
  </.header>

  <.form for={@form} id="role-form" phx-change="validate" phx-submit="save">
    <.input field={@form[:name]} type="text" label="Name" />
    <.input field={@form[:description]} type="text" label="Description" />
    <.input field={@form[:active]} type="checkbox" label="Active" />
    <footer>
      <.button phx-disable-with="Saving..." variant="primary">Save Role</.button>
      <.button navigate={return_path(@return_to, @role)}>Cancel</.button>
    </footer>
  </.form>
</Layouts.app>
```

> `Accounts.change_role/2` (usado arriba en `change_role(role)` y `change_role(role, attrs)`) es un helper que falta en el contexto del paso 4.3 — agrégalo junto a `create_role/1`:
>
> ```elixir
> def change_role(%Role{} = role, attrs \\ %{}) do
>   Role.changeset(role, attrs)
> end
> ```

### 5.2 Usuarios — listado principal con PubSub en vivo

Igual que en el paso 5.1, cada LiveView de usuarios vive en dos archivos: el módulo `.ex` (mount/handle_event/handle_info) y su plantilla colocated `.html.heex` — sin `render/1` inline.

**`lib/user_roles_demo_web/live/user_live/index.ex`**

```elixir
defmodule UserRolesDemoWeb.UserLive.Index do
  use UserRolesDemoWeb, :live_view
  alias UserRolesDemo.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Accounts.subscribe_users()

    {:ok,
     socket
     |> assign(:page_title, "Usuarios")
     |> stream(:users, Accounts.list_users())}
  end

  # Estos mensajes llegan de CUALQUIER pestaña/proceso que haga
  # Accounts.create_user / update_user / delete_user
  @impl true
  def handle_info({:user_created, user}, socket) do
    {:noreply, stream_insert(socket, :users, user)}
  end

  def handle_info({:user_updated, user}, socket) do
    {:noreply, stream_insert(socket, :users, user)}
  end

  def handle_info({:user_deleted, user}, socket) do
    {:noreply, stream_delete(socket, :users, user)}
  end
end
```

**`lib/user_roles_demo_web/live/user_live/index.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    Usuarios
    <:actions>
      <.button variant="primary" navigate={~p"/users/new"}>
        <.icon name="hero-plus" /> Nuevo usuario
      </.button>
    </:actions>
  </.header>

  <.table id="users" rows={@streams.users}>
    <:col :let={{_id, user}} label="Nombre">{user.name}</:col>
    <:col :let={{_id, user}} label="Email">{user.email}</:col>
    <:col :let={{_id, user}} label="Roles">
      {Enum.map_join(user.roles, ", ", & &1.name)}
    </:col>
    <:action :let={{_id, user}}>
      <.link navigate={~p"/users/#{user}"}>Ver</.link>
    </:action>
    <:action :let={{_id, user}}>
      <.link navigate={~p"/users/#{user}/edit"}>Edit</.link>
    </:action>
  </.table>
</Layouts.app>
```

> El botón **"Ver"** de cada fila navega al detalle del usuario (`UserLive.Show`, paso 5.2.1) — a diferencia del generador de roles, que oculta ese link con `sr-only` porque `RoleLive.Show` ya se navega haciendo click en la fila, aquí lo dejamos visible como acción explícita.

> Prueba real: abre `http://localhost:4000/users` en dos pestañas del navegador. Crea un usuario en una — debe aparecer al instante en la otra, sin recargar. Eso confirma que PubSub está funcionando.

#### 5.2.1 Vista de detalle de usuario (`UserLive.Show`)

**`lib/user_roles_demo_web/live/user_live/show.ex`**

```elixir
defmodule UserRolesDemoWeb.UserLive.Show do
  use UserRolesDemoWeb, :live_view
  alias UserRolesDemo.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Usuario")
     |> assign(:user, Accounts.get_user!(id))}
  end
end
```

**`lib/user_roles_demo_web/live/user_live/show.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    Usuario {@user.id}
    <:subtitle>Este es un registro de usuario de tu base de datos.</:subtitle>
    <:actions>
      <.button navigate={~p"/users"}>
        <.icon name="hero-arrow-left" />
      </.button>
      <.button variant="primary" navigate={~p"/users/#{@user}/edit"}>
        <.icon name="hero-pencil-square" /> Editar usuario
      </.button>
    </:actions>
  </.header>

  <.list>
    <:item title="Nombre">{@user.name}</:item>
    <:item title="Email">{@user.email}</:item>
    <:item title="Roles">{Enum.map_join(@user.roles, ", ", & &1.name)}</:item>
  </.list>
</Layouts.app>
```

No olvides agregar la ruta `live "/users/:id", UserLive.Show, :show` (paso 5.3) para que el botón "Ver" funcione.

#### 5.2.2 Formulario de usuario (`UserLive.Form`)

A diferencia de `RoleLive.Form`, este formulario también permite asignar roles al usuario mediante un `<.input type="select" multiple>` y pide la contraseña: al dar de alta (`:new`) es obligatoria (usa `registration_changeset`, paso 6.3); al editar (`:edit`) es opcional — dejarla en blanco conserva la actual, y escribir una nueva la reemplaza (usa `changeset/4`, también del paso 6.3).

**`lib/user_roles_demo_web/live/user_live/form.ex`**

```elixir
defmodule UserRolesDemoWeb.UserLive.Form do
  use UserRolesDemoWeb, :live_view

  alias UserRolesDemo.Accounts
  alias UserRolesDemo.Accounts.User

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:roles, Accounts.list_roles())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user!(id)

    socket
    |> assign(:page_title, "Edit User")
    |> assign(:user, user)
    |> assign(:selected_role_ids, Enum.map(user.roles, & &1.id))
    |> assign(:form, to_form(Accounts.change_user(user)))
  end

  defp apply_action(socket, :new, _params) do
    user = %User{}

    socket
    |> assign(:page_title, "New User")
    |> assign(:user, user)
    |> assign(:selected_role_ids, [])
    |> assign(:form, to_form(Accounts.change_user_registration(user)))
  end

  @impl true
  def handle_event("validate", %{"user" => user_params} = params, socket) do
    changeset = build_changeset(socket, user_params)

    {:noreply,
     socket
     |> assign(:selected_role_ids, role_ids(params))
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => user_params} = params, socket) do
    save_user(socket, socket.assigns.live_action, user_params, role_ids(params))
  end

  defp build_changeset(socket, user_params) do
    case socket.assigns.live_action do
      :new -> Accounts.change_user_registration(socket.assigns.user, user_params)
      :edit -> Accounts.change_user(socket.assigns.user, user_params)
    end
  end

  defp role_ids(params) do
    params
    |> Map.get("role_ids", [])
    |> Enum.map(&String.to_integer/1)
  end

  defp save_user(socket, :edit, user_params, role_ids) do
    case Accounts.update_user(socket.assigns.user, user_params, role_ids) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> push_navigate(to: ~p"/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_user(socket, :new, user_params, role_ids) do
    case Accounts.register_user(user_params, role_ids) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully")
         |> push_navigate(to: ~p"/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
```

**`lib/user_roles_demo_web/live/user_live/form.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>
    {@page_title}
    <:subtitle>Use this form to manage user records in your database.</:subtitle>
  </.header>

  <.form for={@form} id="user-form" phx-change="validate" phx-submit="save">
    <.input field={@form[:name]} type="text" label="Name" />
    <.input field={@form[:email]} type="email" label="Email" />
    <.input
      field={@form[:password]}
      type="password"
      label={if @live_action == :new, do: "Password", else: "New password (leave blank to keep current)"}
    />
    <.input
      type="select"
      id="user-role-ids"
      name="role_ids[]"
      label="Roles"
      multiple
      value={@selected_role_ids}
      options={Enum.map(@roles, &{&1.name, &1.id})}
    />
    <footer>
      <.button phx-disable-with="Saving..." variant="primary">Save User</.button>
      <.button navigate={~p"/users"}>Cancel</.button>
    </footer>
  </.form>
</Layouts.app>
```

> El `<.input type="select" ... multiple name="role_ids[]">` no usa `@form[:role_ids]` porque `role_ids` no es un campo del schema `User` (los roles se asocian vía `many_to_many` en la tabla `users_roles`) — por eso el `name` se fija a mano y `handle_event/3` lo lee de `params["role_ids"]` (función `role_ids/1` arriba), convirtiéndolo a enteros antes de pasarlo a `Accounts.register_user/2` / `update_user/3`.
>
> El campo **Password** cambia de etiqueta según `@live_action`: en `:new` dice "Password" (obligatorio); en `:edit` dice "New password (leave blank to keep current)" y es opcional — si el usuario no escribe nada, la contraseña actual no se toca.
>
> Para que esto funcione hacen falta estas piezas en `Accounts`/`User` respecto al paso 6:
>
> 1. **`Accounts.change_user_registration/2`** — changeset para el formulario de alta, que incluye `:password` como obligatorio:
>
>    ```elixir
>    def change_user_registration(%User{} = user, attrs \\ %{}) do
>      User.registration_changeset(user, attrs, nil, hash_password: false)
>    end
>    ```
>
> 2. **`Accounts.change_user/2`** — changeset para el formulario de edición, con `:password` opcional (y `hash_password: false` durante la validación en vivo, igual que en el registro):
>
>    ```elixir
>    def change_user(%User{} = user, attrs \\ %{}) do
>      User.changeset(user, attrs, nil, hash_password: false)
>    end
>    ```
>
> 3. **`User.changeset/4`** (edición) y **`User.registration_changeset/4`** (alta) comparten la lógica de hasheo condicional (`maybe_hash_password/2`, ver paso 6.3) — al escribir en el formulario, `phx-change="validate"` dispara el changeset en cada tecla; hashear con bcrypt ahí sería lento a propósito (es su función de seguridad) y haría lag el formulario. Por eso el hash solo se calcula cuando `hash_password: true` (el default, usado al guardar de verdad). En edición, además, un password vacío se descarta como "no hay cambio" (`maybe_validate_password/1`, paso 6.3) en vez de fallar la validación de longitud mínima.
>
> 4. **`save_user(socket, :new, ...)` llama a `Accounts.register_user/2`** (paso 6.4) en vez de `create_user/2` — es la función que hashea la contraseña antes de insertar. `create_user/2` sigue existiendo para casos donde se cree un usuario sin password (ej. seeds internos).
>
> 5. **`save_user(socket, :edit, ...)` sigue llamando a `Accounts.update_user/3`** sin cambios — como `User.changeset/4` ahora castea `:password` con `hash_password: true` por default, si el usuario escribió una contraseña nueva, `update_user/3` la hashea y persiste igual que cualquier otro campo; si la dejó en blanco, el `hashed_password` existente no se toca.

### 5.3 Router

```elixir
# lib/user_roles_demo_web/router.ex
scope "/", UserRolesDemoWeb do
  pipe_through :browser

  live "/roles", RoleLive.Index, :index
  live "/roles/new", RoleLive.Form, :new
  live "/roles/:id", RoleLive.Show, :show
  live "/roles/:id/edit", RoleLive.Form, :edit

  live "/users", UserLive.Index, :index
  live "/users/new", UserLive.Form, :new
  live "/users/:id", UserLive.Show, :show
  live "/users/:id/edit", UserLive.Form, :edit
end
```

> Nota: el generador actual de Phoenix separa `new`/`edit` en un único módulo `Form` (en vez de manejarlos dentro de `Index`), y `Show` es su propio LiveView — por eso `RoleLive.Form`/`UserLive.Form` aparecen en el router en lugar de `RoleLive.Index`/`UserLive.Index` para esas rutas.

---

## 6. Autenticación: password + Plug + token (lista para exponer una API)

### 6.0 Enfoque

- Password hasheado con **bcrypt** (`bcrypt_elixir`), nunca en texto plano.
- Al hacer login se firma un **`Phoenix.Token`** con el `secret_key_base` del proyecto — es *stateless* (no necesita tabla `tokens`, no hay que invalidar nada en DB, expira solo por tiempo).
- Ese mismo token se guarda en la **sesión** para la parte web, pero también puede viajar como header `Authorization: Bearer <token>` — así el día que expongas una API JSON (app móvil, otro backend, etc.) reusas el mismo mecanismo de verificación sin tocar el esquema de auth.
- Un solo Plug centraliza la verificación; el router decide si la usa vía sesión (web) o vía header (API).

### 6.1 Dependencia: bcrypt_elixir

```elixir
# mix.exs
defp deps do
  [
    # ...
    {:bcrypt_elixir, "~> 3.0"}
  ]
end
```

```bash
mix deps.get
```

### 6.2 Migración: contraseña hasheada

```bash
mix ecto.gen.migration add_hashed_password_to_users
```

**`priv/repo/migrations/..._add_hashed_password_to_users.exs`**

```elixir
defmodule UserRolesDemo.Repo.Migrations.AddHashedPasswordToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hashed_password, :string, null: false, default: ""
    end
  end
end
```

```bash
mix ecto.migrate
```

### 6.3 Schema `User`: campo virtual `password` + hash

**`lib/user_roles_demo/accounts/user.ex`** (agrega el campo, un changeset de registro, y hace el `changeset/3` que ya tenías para editar capaz de actualizar el password de forma opcional)

```elixir
defmodule UserRolesDemo.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
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
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email])
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
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> maybe_put_roles(roles)
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
```

> `changeset/3` (usado al editar) y `registration_changeset/3` (usado al registrar) comparten `maybe_hash_password/2`: ambos calculan el hash bcrypt solo si `hash_password: true` (el default) y el password cambió y es válido. Al validar "en vivo" (`phx-change`) se pasa `hash_password: false` para no recalcular el hash — deliberadamente lento — en cada tecla; el hash real se calcula recién al guardar. En edición, además, si el campo password llega vacío (`""`), `maybe_validate_password/1` descarta ese cambio con `delete_change/2`: así "dejarlo en blanco" significa "no tocar la contraseña actual" en vez de fallar la validación de longitud mínima.

### 6.4 Contexto `Accounts`: registro, autenticación y tokens

Agrega esto a `lib/user_roles_demo/accounts.ex` (junto a lo que ya tenías del paso 4.3):

```elixir
defmodule UserRolesDemo.Accounts do
  import Ecto.Query, warn: false
  alias UserRolesDemo.Repo
  alias UserRolesDemo.Accounts.{User, Role}
  alias UserRolesDemoWeb.Endpoint

  @pubsub UserRolesDemo.PubSub
  @topic "users"

  # sal de firma del token: cambia esto si algún día quieres invalidar
  # todos los tokens existentes de golpe (ej. tras una brecha de seguridad)
  @token_salt "user auth"
  @token_max_age_seconds 60 * 60 * 24 * 7  # 7 días

  # ... (list_roles/2, get_role!/1, create_role/1, update_role/2,
  #      soft_delete_role/1, restore_role/1, list_users/0, get_user!/1,
  #      create_user/2, update_user/3, delete_user/1, broadcast/2 tal
  #      como quedaron en el paso 4.3) ...

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
      user && Bcrypt.verify_pass(password, user.hashed_password) ->
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
         %User{} = user <- Repo.get(User, user_id) do
      {:ok, Repo.preload(user, :roles)}
    else
      nil -> {:error, :invalid_token}
      {:error, _reason} = error -> error
    end
  end

  def fetch_user_by_token(_), do: {:error, :invalid_token}
end
```

### 6.5 Plug de autenticación (sirve para web con sesión y para API con Bearer)

**`lib/user_roles_demo_web/user_auth.ex`**

```elixir
defmodule UserRolesDemoWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, json: 2, put_flash: 3]

  alias UserRolesDemo.Accounts

  @user_token_session_key :user_token

  ## --- Web: token guardado en sesión ---

  def put_user_token(conn, user) do
    token = Accounts.generate_user_token(user)
    put_session(conn, @user_token_session_key, token)
  end

  def fetch_current_user(conn, _opts) do
    token = get_session(conn, @user_token_session_key)

    case token && Accounts.fetch_user_by_token(token) do
      {:ok, user} -> assign(conn, :current_user, user)
      _ -> assign(conn, :current_user, nil)
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Debes iniciar sesión para continuar")
      |> put_session(:user_return_to, conn.request_path)
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def log_out_user(conn) do
    conn
    |> delete_session(@user_token_session_key)
    |> configure_session(renew: true)
  end

  ## --- API: mismo token, viaja como "Authorization: Bearer <token>" ---

  def fetch_current_user_from_bearer(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.fetch_user_by_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
```

> Nota el patrón: en el router vamos a hacer `import UserRolesDemoWeb.UserAuth` y luego `plug :fetch_current_user`. Como `plug :atom` resuelve la función en el contexto del módulo donde se declara el pipeline, importar el módulo hace que las funciones públicas de arriba queden disponibles ahí mismo — es el mismo patrón que usa `mix phx.gen.auth`.

### 6.6 Router: pipelines de sesión, rutas de login/logout y pipeline `:api`

```elixir
# lib/user_roles_demo_web/router.ex
defmodule UserRolesDemoWeb.Router do
  use UserRolesDemoWeb, :router
  import UserRolesDemoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UserRolesDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  # ¡Ojo con el nombre! No lo llames `:require_authenticated_user` — es el
  # mismo nombre que la función importada de `UserAuth` que usás como `plug`
  # abajo, y Phoenix rechaza el router con
  # `** (ArgumentError) cannot define pipeline named :require_authenticated_user
  # because there is an import from UserRolesDemoWeb.UserAuth with the same name`.
  pipeline :authenticated do
    plug :require_authenticated_user
  end

  # pipeline listo para cuando expongas endpoints JSON
  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :fetch_current_user_from_bearer
  end

  scope "/", UserRolesDemoWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    get "/users/reset-password", UserResetPasswordController, :new
    post "/users/reset-password", UserResetPasswordController, :create
    get "/users/reset-password/:token", UserResetPasswordController, :edit
    put "/users/reset-password/:token", UserResetPasswordController, :update
  end

  scope "/", UserRolesDemoWeb do
    pipe_through [:browser, :authenticated]

    live "/roles", RoleLive.Index, :index
    live "/roles/new", RoleLive.Form, :new
    live "/roles/:id", RoleLive.Show, :show
    live "/roles/:id/edit", RoleLive.Form, :edit

    live "/users", UserLive.Index, :index
    live "/users/new", UserLive.Form, :new
    live "/users/:id", UserLive.Show, :show
    live "/users/:id/edit", UserLive.Form, :edit
  end

  # API versionada: /api/v1/... — login público (emite token) + rutas
  # protegidas con Bearer. El prefijo /v1 deja lugar para un /api/v2 el día
  # que haya que romper compatibilidad sin tocar a los clientes existentes
  # (ver sección 8 para más detalle sobre por qué versionar así).
  scope "/api/v1", UserRolesDemoWeb.API do
    pipe_through :api

    post "/login", SessionController, :create
  end

  scope "/api/v1", UserRolesDemoWeb.API do
    pipe_through [:api, :api_auth]

    get "/me", UserController, :me
  end
end
```

> La sección 5.3 original (rutas sin proteger) queda reemplazada por este bloque: ahora `/roles` y `/users` exigen sesión iniciada.

### 6.7 Controlador de sesión (web)

**`lib/user_roles_demo_web/controllers/session_controller.ex`**

```elixir
defmodule UserRolesDemoWeb.SessionController do
  use UserRolesDemoWeb, :controller

  alias UserRolesDemo.Accounts
  alias UserRolesDemoWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.put_user_token(user)
        |> redirect(to: ~p"/users")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Email o contraseña inválidos")
        |> render(:new)
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/login")
  end
end
```

**`lib/user_roles_demo_web/controllers/session_html.ex`**

```elixir
defmodule UserRolesDemoWeb.SessionHTML do
  use UserRolesDemoWeb, :html

  embed_templates "session_html/*"
end
```

**`lib/user_roles_demo_web/controllers/session_html/new.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <.header>Iniciar sesión</.header>

  <.form for={%{}} as={:user} action={~p"/login"}>
    <.input name="email" type="email" label="Email" value="" required />
    <.input name="password" type="password" label="Contraseña" value="" required />
    <footer>
      <.button phx-disable-with="Entrando..." variant="primary">Entrar</.button>
      <.link navigate={~p"/users/reset-password"}>¿Olvidaste tu contraseña?</.link>
    </footer>
  </.form>
</Layouts.app>
```

> `<.simple_form>` **no existe** en `core_components.ex` de Phoenix 1.8 (era un helper de versiones viejas de `phx.gen.auth`) — si lo usás, Phoenix compila bien pero la página explota en runtime con `UndefinedFunctionError`. Usá `<.form>` + `<.input>` directo, igual que en el resto de la app (paso 5). Y como aquí no hay `field={@form[...]}` (no hay changeset detrás, es un form plano), tenés que pasar `value=""` a mano en cada `<.input>` — el componente no tiene un default para `:value` y sin `field` no hay de dónde sacarlo; si lo omitís, explota con `** (KeyError) key :value not found`.

### 6.8 API lista para exponer: login que emite token + endpoint protegido

> Estos controllers quedan montados bajo `/api/v1` (sección 8) en vez de `/api` sin versión — el nombre del módulo (`UserRolesDemoWeb.API...`) no cambia, solo el prefijo de la ruta en el router.

**`lib/user_roles_demo_web/controllers/api/session_controller.ex`**

```elixir
defmodule UserRolesDemoWeb.API.SessionController do
  use UserRolesDemoWeb, :controller

  alias UserRolesDemo.Accounts

  # POST /api/v1/login  {"email": "...", "password": "..."} -> {"token": "..."}
  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        json(conn, %{token: Accounts.generate_user_token(user)})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid credentials"})
    end
  end
end
```

**`lib/user_roles_demo_web/controllers/api/user_controller.ex`**

```elixir
defmodule UserRolesDemoWeb.API.UserController do
  use UserRolesDemoWeb, :controller

  # GET /api/v1/me  (requiere "Authorization: Bearer <token>")
  def me(conn, _params) do
    render(conn, :me, user: conn.assigns.current_user)
  end
end
```

**`lib/user_roles_demo_web/controllers/api/role_json.ex`**

```elixir
defmodule UserRolesDemoWeb.API.RoleJSON do
  alias UserRolesDemo.Accounts.Role

  @doc """
  Renders a single role. Reutilizado por `UserJSON` para serializar la
  asociación `many_to_many :roles` de `User` (y por cualquier otro endpoint
  que devuelva roles, ej. un futuro `GET /api/v1/roles`).
  """
  def data(%Role{} = role) do
    %{
      id: role.id,
      name: role.name,
      description: role.description,
      active: role.active
    }
  end
end
```

**`lib/user_roles_demo_web/controllers/api/user_json.ex`**

```elixir
defmodule UserRolesDemoWeb.API.UserJSON do
  alias UserRolesDemo.Accounts.User
  alias UserRolesDemoWeb.API.RoleJSON

  @doc """
  Renders the authenticated user (`GET /api/v1/me`).
  """
  def me(%{user: user}), do: data(user)

  defp data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      # `:roles` es un `many_to_many` (join via `users_roles`) — se preload
      # en `Accounts.fetch_user_by_token/1` antes de llegar aquí. Delegamos
      # a `RoleJSON.data/1` para no duplicar el shape de un role, en vez de
      # devolver solo `& &1.name` (perdería `id`/`description`/`active`).
      roles: Enum.map(user.roles, &RoleJSON.data/1)
    }
  end
end
```

> El JSON de `/api/v1/me` queda `{"id":..., "roles":[{"id":1,"name":"admin","description":"...","active":true}, ...]}` — cada rol con su shape completo, no solo el nombre.

> `Phoenix.View` ya no existe (lo dice también la guía de Ecto más abajo) — desde Phoenix 1.6/1.7 el patrón para JSON es un módulo `*JSON` por controller, con una función pública por acción. El controller solo arma los `assigns` y llama `render(conn, :accion, assigns)`; Phoenix resuelve el módulo (`UserController` → `UserJSON`, por convención de sufijo) y llama a `UserJSON.me(assigns)`. Es el mismo mecanismo que ya usa `UserRolesDemoWeb.ErrorJSON` (generado por `phx.new`) para los errores 404/500 — separa "qué datos armo" (el `*JSON`) de "qué acción HTTP corresponde" (el controller), y es trivial de testear llamando `UserJSON.me(%{user: user})` directo, sin pasar por una conexión HTTP.

> Si en el futuro esta API la consume un frontend en otro dominio (SPA, app móvil web), agrega [`cors_plug`](https://hex.pm/packages/cors_plug) al pipeline `:api` — no hace falta ahora para un cliente same-origin o un cliente nativo/mobile.

### 6.9 Crear un usuario de prueba y probar el flujo completo

En `priv/repo/seeds.exs`:

```elixir
alias UserRolesDemo.Accounts

{:ok, _admin} =
  Accounts.register_user(%{
    name: "Admin",
    email: "admin@example.com",
    password: "supersecreta123"
  })
```

```bash
mix run priv/repo/seeds.exs
mix phx.server
```

**Login web:** abre `http://localhost:4000/login`, entra con `admin@example.com` / `supersecreta123` — te redirige a `/users` con la sesión activa (si no habías iniciado sesión, `/users` te habría mandado antes a `/login`).

**Login vía API (mismo mecanismo, listo para un cliente externo):**

```bash
curl -s -X POST http://localhost:4000/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"supersecreta123"}'
# => {"token":"SFMyNTY...."}

TOKEN="pega-aqui-el-token"

curl -s http://localhost:4000/api/v1/me \
  -H "Authorization: Bearer $TOKEN"
# => {"id":1,"name":"Admin","email":"admin@example.com","roles":[]}
```

### 6.10 Reset de password ("olvidé mi contraseña")

Esta pieza es una de las que trae `mix phx.gen.auth` de fábrica (ver sección 12.1) y que acá portamos a mano para que conviva con el `Accounts.User`/`UserAuth` propios, sin agregar una tabla de tokens nueva.

**Diseño:** en vez de guardar los tokens de reset en una tabla (como hace `phx.gen.auth` con `users_tokens`, para poder invalidarlos borrando la fila), seguimos usando `Phoenix.Token` firmado y sin estado — igual que `generate_user_token/1` del paso 6.4 — pero el *payload* que firmamos incluye un hash corto (`:erlang.phash2/1`) del `hashed_password` vigente en el momento de emitir el link:

```elixir
%{id: user.id, hash: :erlang.phash2(user.hashed_password)}
```

Al verificar, se recalcula ese hash sobre el `hashed_password` **actual** del usuario — si no coincide (porque la contraseña ya cambió, sea por este mismo reset o por cualquier otro motivo), el token se rechaza. Resultado: cualquier link de reset queda invalidado automáticamente en el instante en que se usa (o en que la contraseña cambia por otra vía), sin tocar la base de datos para nada más que leer el usuario. El costo es que el link solo vive `20` minutos (configurable) en vez de hasta que alguien lo use — un trade-off razonable para un flujo que el usuario puede volver a pedir cuando quiera.

**`lib/user_roles_demo/accounts/user.ex`** — agrega el changeset que solo toca `:password` (edición ya tiene el suyo del paso 6.3, pero este no exige `:name`/`:email`):

```elixir
# reseteo de password ("olvidé mi contraseña"): solo pide/valida el password,
# sin tocar name/email/roles.
def password_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:password])
  |> validate_required([:password])
  |> validate_length(:password, min: 8, max: 72)
  |> maybe_hash_password(opts)
end
```

**`lib/user_roles_demo/accounts/user_notifier.ex`** — usa el `UserRolesDemo.Mailer` (Swoosh) que ya trae `phx.new`:

```elixir
defmodule UserRolesDemo.Accounts.UserNotifier do
  @moduledoc """
  Builds and delivers transactional emails for the `Accounts` context
  (currently just the reset-password instructions).
  """

  import Swoosh.Email

  alias UserRolesDemo.Mailer

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"UserRolesDemo", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """
    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this email. The link
    above expires shortly and stops working as soon as a new password is set.

    ==============================
    """)
  end
end
```

**`lib/user_roles_demo/accounts.ex`** — agrega junto a lo demás (necesita `alias UserRolesDemo.Accounts.{Role, User, UserNotifier}` arriba):

```elixir
@reset_password_salt "reset password"
# 20 minutos — el usuario siempre puede pedir un link nuevo.
@reset_password_token_max_age_seconds 60 * 20

def get_user_by_email(email) when is_binary(email) do
  User
  |> preload(:roles)
  |> Repo.get_by(email: email)
end

def change_user_password(%User{} = user, attrs \\ %{}) do
  User.password_changeset(user, attrs, hash_password: false)
end

def reset_user_password(%User{} = user, attrs) do
  user
  |> User.password_changeset(attrs)
  |> Repo.update()
end

def generate_user_reset_password_token(%User{} = user) do
  payload = %{id: user.id, hash: :erlang.phash2(user.hashed_password)}
  Phoenix.Token.sign(Endpoint, @reset_password_salt, payload)
end

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

# Mantiene a `Accounts` desacoplado del router: quien llama pasa la función
# que construye la URL (`&url(~p"/users/reset-password/#{&1}")`).
def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
    when is_function(reset_password_url_fun, 1) do
  token = generate_user_reset_password_token(user)
  UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(token))
end
```

> `get_user_by_email/1` precarga `:roles` igual que `get_user!/1` (paso 4.3) — si no lo hacés, el user que devuelve trae `roles: #Ecto.Association.NotLoaded<...>`, y cualquier código posterior que intente reasignar roles sobre ese user (`Accounts.update_user/3` → `User.changeset/4` → `put_assoc(:roles, ...)`) revienta con `Ecto.Changeset` reclamando que la asociación no está cargada. Como esta función puede usarse en cualquier flujo que después toque al user (no solo en el reset de password), conviene dejarla precargada desde acá en vez de confiar en que cada caller se acuerde de hacerlo.

**`lib/user_roles_demo_web/controllers/user_reset_password_controller.ex`**

```elixir
defmodule UserRolesDemoWeb.UserResetPasswordController do
  use UserRolesDemoWeb, :controller

  # `to_form/2` no está disponible por default en un controller (a diferencia
  # de LiveViews/HTML, los controllers no hacen `use Phoenix.Component`).
  import Phoenix.Component, only: [to_form: 1]

  alias UserRolesDemo.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"email" => email}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    # mismo mensaje exista o no el email — evita filtrar qué emails están
    # registrados (igual que `authenticate_user/2` del paso 6.4).
    conn
    |> put_flash(
      :info,
      "Si tu email existe en el sistema, en breve recibirás instrucciones para restablecer la contraseña."
    )
    |> redirect(to: ~p"/login")
  end

  def edit(conn, %{"token" => token}) do
    case Accounts.fetch_user_by_reset_password_token(token) do
      {:ok, user} ->
        render(conn, :edit,
          token: token,
          form: to_form(Accounts.change_user_password(user))
        )

      {:error, _reason} ->
        conn
        |> put_flash(:error, "El link para restablecer la contraseña es inválido o ya expiró.")
        |> redirect(to: ~p"/users/reset-password")
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.fetch_user_by_reset_password_token(token) do
      {:ok, user} ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Contraseña actualizada correctamente.")
            |> redirect(to: ~p"/login")

          {:error, changeset} ->
            render(conn, :edit, token: token, form: to_form(changeset))
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "El link para restablecer la contraseña es inválido o ya expiró.")
        |> redirect(to: ~p"/users/reset-password")
    end
  end
end
```

**`lib/user_roles_demo_web/controllers/user_reset_password_html.ex`**

```elixir
defmodule UserRolesDemoWeb.UserResetPasswordHTML do
  use UserRolesDemoWeb, :html

  embed_templates "user_reset_password_html/*"
end
```

**`lib/user_roles_demo_web/controllers/user_reset_password_html/new.html.heex`** (pide el email)

```heex
<Layouts.app flash={@flash}>
  <.header>
    ¿Olvidaste tu contraseña?
    <:subtitle>Te enviamos un link para restablecerla.</:subtitle>
  </.header>

  <.form for={%{}} as={:user} action={~p"/users/reset-password"}>
    <.input name="email" type="email" label="Email" value="" required />
    <footer>
      <.button phx-disable-with="Enviando..." variant="primary">Enviar instrucciones</.button>
      <.link navigate={~p"/login"}>Volver a iniciar sesión</.link>
    </footer>
  </.form>
</Layouts.app>
```

**`lib/user_roles_demo_web/controllers/user_reset_password_html/edit.html.heex`** (pide la contraseña nueva; aquí sí usamos `@form` con changeset porque necesitamos mostrar errores de validación)

```heex
<Layouts.app flash={@flash}>
  <.header>Elegí una nueva contraseña</.header>

  <.form for={@form} id="reset-password-form" action={~p"/users/reset-password/#{@token}"} method="put">
    <.input field={@form[:password]} type="password" label="Nueva contraseña" required />
    <footer>
      <.button phx-disable-with="Guardando..." variant="primary">Restablecer contraseña</.button>
      <.link navigate={~p"/login"}>Cancelar</.link>
    </footer>
  </.form>
</Layouts.app>
```

Las rutas ya quedaron en el bloque del router del paso 6.6 (`/users/reset-password` y `/users/reset-password/:token`, públicas, sin `:authenticated`). Y en `new.html.heex` del login (paso 6.7) agregamos el link `¿Olvidaste tu contraseña?` que apunta a `/users/reset-password`.

**Probarlo:** en dev, Swoosh usa `Swoosh.Adapters.Local` (ver `config/config.exs`) — el email no sale a internet, queda en un buzón que podés ver en `http://localhost:4000/dev/mailbox`. Flujo completo:

1. Entrá a `http://localhost:4000/users/reset-password`, poné el email de un usuario existente (ej. `admin@example.com` del seed) y enviá.
2. Abrí `http://localhost:4000/dev/mailbox`, hacé click en el email "Reset password instructions" y copiá el link.
3. Pegá el link en el navegador, poné una contraseña nueva (mínimo 8 caracteres) y confirmá.
4. Entrá a `/login` con el email y la contraseña nueva — debería funcionar. La contraseña vieja ya no sirve, y si volvés a abrir el mismo link del email, va a decir que es inválido (porque el `hashed_password` ya cambió).

---

## 7. Correr y probar

```bash
mix setup       # deps.get + ecto.setup + assets.setup
mix phx.server
```

Abre `http://localhost:4000/roles` para el CRUD de roles con borrado lógico, y `http://localhost:4000/users` para ver el listado con PubSub en vivo.

---

## 8. Exponer una API versionada (`/api/v1`)

### 8.0 Por qué versionar la URL

Los endpoints de API del paso 6.8 (`POST /api/login`, `GET /api/me`) ya existen y alguien externo podría estar consumiéndolos. El día que necesites un cambio incompatible (ej. cambiar la forma del JSON de respuesta, o el nombre de un campo) sin romper a esos clientes, necesitás poder ofrecer las dos formas al mismo tiempo. La forma más simple de dejar esa puerta abierta desde el principio es versionar en la URL: `/api/v1/...` en vez de `/api/...` sin versión.

- **No hace falta "v2" todavía** — la ventaja es puramente que el día de mañana, agregar `/api/v2/...` en paralelo a `/api/v1/...` es un `scope` más en el router, no una migración de todos los clientes existentes de una.
- **El módulo Elixir no necesita llevar la versión en el nombre** mientras solo exista `v1` — `UserRolesDemoWeb.API.SessionController` sigue sirviendo `/api/v1/login` tal cual. Recién cuando aparezca un `v2` con comportamiento distinto conviene separar en `UserRolesDemoWeb.API.V1.*` / `UserRolesDemoWeb.API.V2.*`, para no mezclar lógica de ambas versiones en el mismo controller.

### 8.1 Cambiar el prefijo en el router

Es el único cambio real: el `scope` pasa de `"/api"` a `"/api/v1"`. Los controllers (`UserRolesDemoWeb.API.SessionController`/`UserController`, paso 6.8) no cambian.

```elixir
# lib/user_roles_demo_web/router.ex

# API versionada: /api/v1/... — login público (emite token) + rutas
# protegidas con Bearer. El prefijo /v1 deja lugar para un /api/v2 el día
# que haya que romper compatibilidad sin tocar a los clientes existentes.
scope "/api/v1", UserRolesDemoWeb.API do
  pipe_through :api

  post "/login", SessionController, :create
end

scope "/api/v1", UserRolesDemoWeb.API do
  pipe_through [:api, :api_auth]

  get "/me", UserController, :me
end
```

> Esto reemplaza el bloque `scope "/api", UserRolesDemoWeb.API do ... end` del paso 6.6/6.8 — `/api/login` y `/api/me` (sin versión) dejan de existir; ahora son `/api/v1/login` y `/api/v1/me`.

### 8.2 Probarlo

Los mismos comandos del paso 6.9, con `/v1` agregado:

```bash
curl -s -X POST http://localhost:4000/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"supersecreta123"}'
# => {"token":"SFMyNTY...."}

TOKEN="pega-aqui-el-token"

curl -s http://localhost:4000/api/v1/me \
  -H "Authorization: Bearer $TOKEN"
# => {"id":1,"name":"Admin","email":"admin@example.com","roles":[]}

# la ruta vieja sin versión ya no existe:
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/api/me
# => 404
```

### 8.3 GraphQL (vía Absinthe) como complemento a la REST

REST y GraphQL no son mutuamente excluyentes — podés tener los dos. Esta sección agrega un endpoint GraphQL **al lado** de `/api/v1` (no lo reemplaza), usando [Absinthe](https://hexdocs.pm/absinthe), la librería estándar de GraphQL para Elixir/Phoenix.

**Diferencia clave con el versionado de 8.0/8.1:** GraphQL **no se versiona en la URL**. En vez de `/api/v2/graphql` el día de un cambio, el schema evoluciona agregando campos nuevos o marcando los viejos como `@deprecated` — el cliente pide exactamente los campos que necesita, así que agregar campos nunca rompe a nadie, y sacar un campo se avisa con deprecación antes de borrarlo. Por eso el endpoint vive en `/api/graphql`, sin `/v1`.

#### 8.3.1 Dependencias

```elixir
# mix.exs
defp deps do
  [
    # ...
    {:absinthe, "~> 1.12"},
    {:absinthe_plug, "~> 1.5"}
  ]
end
```

```bash
mix deps.get
```

#### 8.3.2 El schema: tipos, query y mutation

**`lib/user_roles_demo_web/graphql/schema.ex`**

```elixir
defmodule UserRolesDemoWeb.GraphQL.Schema do
  use Absinthe.Schema

  alias UserRolesDemoWeb.GraphQL.Resolvers

  object :role do
    field :id, :id
    field :name, :string
    field :description, :string
    field :active, :boolean
  end

  object :user do
    field :id, :id
    field :name, :string
    field :email, :string
    field :roles, list_of(:role)
  end

  object :login_payload do
    field :token, :string
    field :user, :user
  end

  query do
    @desc "The currently authenticated user (requires Authorization: Bearer <token>)"
    field :me, :user do
      resolve(&Resolvers.Accounts.me/3)
    end

    @desc "Active roles"
    field :roles, list_of(:role) do
      resolve(&Resolvers.Accounts.roles/3)
    end
  end

  mutation do
    @desc "Authenticates with email + password and returns a Bearer token"
    field :login, :login_payload do
      arg(:email, non_null(:string))
      arg(:password, non_null(:string))
      resolve(&Resolvers.Accounts.login/3)
    end
  end
end
```

> `field :roles, list_of(:role)` dentro de `object :user` resuelve solo con `user.roles` (el resolver default de Absinthe es `Map.get(parent, field_name)`) — por eso **tiene** que venir precargado desde el resolver de `me` (lo está, porque `Accounts.fetch_user_by_token/1` del paso 6.4 ya hace `preload(:roles)`). Si llegara sin precargar, Absinthe fallaría al serializar un `Ecto.Association.NotLoaded`.

**`lib/user_roles_demo_web/graphql/resolvers/accounts.ex`**

```elixir
defmodule UserRolesDemoWeb.GraphQL.Resolvers.Accounts do
  alias UserRolesDemo.Accounts

  def me(_parent, _args, %{context: %{current_user: user}}), do: {:ok, user}
  def me(_parent, _args, _resolution), do: {:error, "unauthenticated"}

  def roles(_parent, _args, _resolution), do: {:ok, Accounts.list_roles()}

  def login(_parent, %{email: email, password: password}, _resolution) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} -> {:ok, %{token: Accounts.generate_user_token(user), user: user}}
      {:error, :unauthorized} -> {:error, "invalid credentials"}
    end
  end
end
```

> Nota cómo `login/3` y `me/3`/`roles/3` reutilizan exactamente las mismas funciones de `Accounts` (`authenticate_user/2`, `generate_user_token/1`, `fetch_user_by_token/1` vía el contexto, `list_roles/1`) que ya usan `SessionController`/`UserController` en REST (pasos 6.4/6.8) — GraphQL es otra fachada sobre el mismo contexto, no una lógica de negocio paralela.

#### 8.3.3 El contexto: cómo le llega `current_user` a los resolvers

A diferencia de un controller REST, un resolver de Absinthe no recibe el `conn` — recibe una `%Absinthe.Resolution{}` con un `context` que armás vos mismo en un plug, **antes** de que la query llegue al schema.

**`lib/user_roles_demo_web/graphql/context.ex`**

```elixir
defmodule UserRolesDemoWeb.GraphQL.Context do
  @behaviour Plug

  import Plug.Conn

  alias UserRolesDemo.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    Absinthe.Plug.put_options(conn, context: build_context(conn))
  end

  defp build_context(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.fetch_user_by_token(token) do
      %{current_user: user}
    else
      _ -> %{}
    end
  end
end
```

> Mismo header `Authorization: Bearer <token>` y mismo `Accounts.fetch_user_by_token/1` que ya usa `UserAuth.fetch_current_user_from_bearer/2` en REST (paso 6.5) — es el mismo token, dos fachadas distintas lo verifican igual. Si no hay token o es inválido, el contexto queda `%{}` (sin `current_user`) en vez de cortar la conexión; es la query `me` la que decide devolver su propio error (`"unauthenticated"`) — otras queries públicas, como `roles`, siguen funcionando sin token.

#### 8.3.4 Router: montar el endpoint (y GraphiQL en dev)

```elixir
# lib/user_roles_demo_web/router.ex

pipeline :graphql_context do
  plug UserRolesDemoWeb.GraphQL.Context
end

# GraphiQL (solo dev) necesita poder servir HTML además de JSON —
# con el pipeline :api (solo "json") tira Phoenix.NotAcceptableError.
pipeline :graphiql do
  plug :accepts, ["html", "json"]
end

# GraphQL: no versionamos la URL (/api/graphql, no /api/v1/graphql) — ver 8.3.
scope "/api" do
  pipe_through [:api, :graphql_context]

  forward "/graphql", Absinthe.Plug, schema: UserRolesDemoWeb.GraphQL.Schema
end

if Application.compile_env(:user_roles_demo, :dev_routes) do
  scope "/api" do
    pipe_through [:graphiql, :graphql_context]

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: UserRolesDemoWeb.GraphQL.Schema,
      interface: :simple
  end
end
```

> `forward` delega **toda** la sub-ruta a otro plug (`Absinthe.Plug`/`Absinthe.Plug.GraphiQL`) — por eso no hay `get`/`post` individuales, Absinthe maneja el método HTTP y el parsing del body internamente.

#### 8.3.5 Probarlo

```bash
# query pública, sin token
curl -s -X POST http://localhost:4000/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ roles { id name active } }"}'
# => {"data":{"roles":[{"active":true,"id":"1","name":"admin"}, ...]}}

# mutation de login, devuelve token + user anidado con sus roles
curl -s -X POST http://localhost:4000/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { login(email: \"admin@example.com\", password: \"supersecreta123\") { token user { id name roles { name } } } }"}'

# me, con el token de arriba
TOKEN="pega-aqui-el-token"
curl -s -X POST http://localhost:4000/api/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ me { id name email roles { id name } } }"}'

# me, sin token -> error controlado, no un 401/500
curl -s -X POST http://localhost:4000/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ me { id name } }"}'
# => {"data":{"me":null},"errors":[{"message":"unauthenticated", ...}]}
```

**En el navegador:** abrí `http://localhost:4000/api/graphiql` — es una IDE interactiva para probar queries/mutations contra el schema, con autocompletado (lee el schema vía introspección). Solo está montada cuando `dev_routes: true` (paso 8.3.4), igual que el LiveDashboard.

> Si probás `/api/graphiql` con `curl` sin más, da `400 "No query document supplied"` en vez de la página — es porque Absinthe decide servir la UI de GraphiQL solo cuando el header `Accept` pide `text/html` explícitamente (lo que todo navegador manda por default); `curl` sin `-H "Accept: text/html"` manda `*/*` y Absinthe lo trata como un pedido de API plano. No es un bug, es cómo Absinthe distingue "un browser abriendo la página" de "un cliente API pegándole directo".

---

## 9. Integrar el proyecto a GitHub

```bash
git init
git add .
git status   # revisa que no se cuele .env, secretos, etc.

git commit -m "feat: proyecto inicial Phoenix LiveView con Users, Roles (many_to_many) y borrado lógico"

# crea el repo en GitHub (requiere gh CLI autenticado con `gh auth login`)
gh repo create user_roles_demo --private --source=. --remote=origin

git branch -M main
git push -u origin main
```

Flujo sugerido para siguientes cambios:

```bash
git checkout -b feat/roles-crud
# ... cambios ...
git add .
git commit -m "feat: CRUD de roles con borrado lógico"
git push -u origin feat/roles-crud
gh pr create --fill
```

---

## 10. Integración continua (CI) con GitHub Actions

Usamos [`erlef/setup-beam`](https://github.com/erlef/setup-beam), la action oficial de la comunidad Erlang/Elixir — internamente instala las mismas versiones que fijaste con asdf, así que el build en CI es reproducible respecto a tu M1.

### 10.1 Servicio de Postgres + pipeline de test

```bash
mkdir -p .github/workflows
```

**`.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      db:
        image: postgres:16
        ports: ["5432:5432"]
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: user_roles_demo_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      MIX_ENV: test
      DATABASE_URL: ecto://postgres:postgres@localhost/user_roles_demo_test

    steps:
      - uses: actions/checkout@v4

      # Lee las versiones directo de .tool-versions -> mismo par que usas local con asdf
      - uses: erlef/setup-beam@v1
        with:
          version-file: .tool-versions
          version-type: strict

      - name: Restaurar caché de deps y build
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Instalar dependencias
        run: mix deps.get

      - name: Compilar sin warnings
        run: mix compile --warnings-as-errors

      - name: Verificar formato
        run: mix format --check-formatted

      - name: Crear y migrar la base de datos de test
        run: mix ecto.create --quiet && mix ecto.migrate --quiet

      - name: Ejecutar tests
        run: mix test
```

> Como `.tool-versions` ya existe en la raíz del proyecto (paso 3.1), `setup-beam` lo lee automáticamente — si cambias de versión de Erlang/Elixir localmente con asdf, CI queda sincronizado sin tocar el workflow.

### 10.2 Probarlo y subirlo

```bash
git add .github/workflows/ci.yml
git commit -m "ci: pipeline de test con Postgres via GitHub Actions"
git push
```

Ve a la pestaña **Actions** del repo en GitHub para ver el workflow correr. Si quieres que sea obligatorio antes de mergear, actívalo como *required status check* en Settings → Branches → Branch protection rules.

---

## 11. Despliegue continuo (CD) local — opcional

En lugar de un proveedor en la nube, el deploy corre **en tu propia Mac**: un *self-hosted runner* de GitHub Actions toma el job `deploy`, compila un `mix release`, corre las migraciones y reinicia la app con `launchd`. No hace falta Docker.

```
push a main ──► job test (ubuntu, GitHub) ──► job deploy (tu Mac, self-hosted)
                                                 │
                                                 ├─ mix release → ~/apps/user_roles_demo/releases/<sha>
                                                 ├─ bin/migrate
                                                 ├─ current → releases/<sha>
                                                 └─ launchctl kickstart (reinicia la app)
```

Archivos involucrados:

| Archivo | Para qué |
|---|---|
| `lib/user_roles_demo/release.ex`, `rel/overlays/bin/{server,migrate}` | Generados por `mix phx.gen.release`: arrancar el server y migrar desde el release (sin `mix`) |
| `deploy/local/install.sh` | Preparación única: secretos, base de datos de prod y servicio de `launchd` |
| `deploy/local/deploy.sh` | El deploy en sí. Lo corre el workflow, pero también lo puedes correr a mano |
| `deploy/local/start.sh` | Lo que ejecuta `launchd`: carga `prod.env` y arranca `current/bin/server` |
| `deploy/local/com.user_roles_demo.plist` | Plantilla del servicio de `launchd` |
| `deploy/local/prod.env.example` | Plantilla de variables de entorno; el archivo real vive fuera del repo |

> ⚠️ **Seguridad: repo público + self-hosted runner.** En un repo público, cualquiera puede abrir un PR desde un fork que modifique el workflow para que corra en *tu* runner, es decir, código ajeno ejecutándose en tu Mac. Antes de registrar el runner, haz una de estas dos cosas:
> - Haz el repo **privado** (lo más simple), o
> - En *Settings → Actions → General → Fork pull request workflows*, activa **Require approval for all external contributors** y nunca apruebes PRs de desconocidos.

### 11.1 Generar los archivos de release

```bash
mix phx.gen.release
```

Crea `lib/user_roles_demo/release.ex` (con `UserRolesDemo.Release.migrate/0`) y los scripts `rel/overlays/bin/server` y `rel/overlays/bin/migrate`, que se copian dentro del release.

### 11.2 Preparar tu Mac (una sola vez)

Requisitos: Postgres corriendo en `localhost` (Postgres.app o Homebrew) y Erlang/Elixir instalados con asdf (los mismos de `.tool-versions`).

```bash
deploy/local/install.sh
```

Esto hace tres cosas:

1. Crea `~/.config/user_roles_demo/prod.env` (permisos `600`) con un `SECRET_KEY_BASE` recién generado. La app de prod escucha en `PORT=4001`, para no chocar con `mix phx.server` en el 4000.
2. Crea la base de datos `user_roles_demo_prod`.
3. Registra el servicio `com.user_roles_demo` en `launchd`. Arranca al iniciar sesión y se reinicia solo si se cae con error.

Primer deploy manual, para comprobar que todo funciona antes de meter GitHub en medio:

```bash
deploy/local/deploy.sh
open http://localhost:4001
```

> **Tailwind en macOS arm64:** el binario de Tailwind 4.x que descarga `mix assets.setup` puede venir con una firma de código inválida, y macOS lo mata (`exited with 137`). `deploy.sh` lo detecta con `codesign -v` y lo re-firma ad hoc (`codesign --force --sign -`). Si te pasa en desarrollo, corre ese mismo comando sobre `_build/tailwind-*`.

### 11.3 Registrar el self-hosted runner

En GitHub: *Settings → Actions → Runners → New self-hosted runner → macOS / ARM64*. Sigue los comandos que te muestra (descargar y `./config.sh ...`). Cuando pregunte por **labels adicionales**, agrega:

```
user-roles-local
```

El workflow pide `[self-hosted, macOS, ARM64, user-roles-local]`. Ese label propio asegura que el deploy caiga en *esta* Mac y no en otro runner que registres después.

Para que el runner arranque solo con tu sesión, instálalo como servicio desde la carpeta del runner:

```bash
./svc.sh install
./svc.sh start
```

> El runner corre como **tu usuario**, así que el deploy puede usar `launchctl` sobre tu sesión gráfica (`gui/<uid>`). Por eso es un *LaunchAgent* (en `~/Library/LaunchAgents`) y no un *LaunchDaemon*.

### 11.4 Workflow de despliegue

Job adicional al final de **`.github/workflows/ci.yml`**:

```yaml
  # CD local: corre en el self-hosted runner de tu Mac (ver deploy/local/ y la
  # sección 11 de la guía). Solo en push a main y solo si `test` pasó.
  deploy:
    needs: test
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: [self-hosted, macOS, ARM64, user-roles-local]
    # un deploy a la vez; si llega otro push, espera en vez de cancelar
    concurrency:
      group: deploy-local
      cancel-in-progress: false

    steps:
      - uses: actions/checkout@v4

      # el runner no carga tu shell (.zshrc): agrega a mano asdf y Homebrew
      - name: Herramientas en PATH
        run: |
          echo "$HOME/.asdf/shims" >> "$GITHUB_PATH"
          echo "/opt/homebrew/bin" >> "$GITHUB_PATH"

      - name: Desplegar release
        run: deploy/local/deploy.sh
        env:
          RELEASE_SHA: ${{ github.sha }}
```

Con esto, cada push a `main` corre los tests y, si pasan, despliega en tu Mac. Los pushes a `feat/**` y los PRs solo corren los tests, por la condición del `if`.

Qué hace `deploy.sh`, en orden:

1. Carga `~/.config/user_roles_demo/prod.env`.
2. `mix deps.get --only prod`, `mix compile`, `mix assets.setup` y `mix assets.deploy` con `MIX_ENV=prod`.
3. `mix release --path ~/apps/user_roles_demo/releases/<sha>`. El release queda fuera del checkout del runner, que se limpia en cada job.
4. `bin/migrate` del release nuevo, **antes** de activarlo. Si una migración falla, la versión anterior sigue arriba.
5. Mueve el symlink `current` al release nuevo y reinicia con `launchctl kickstart -k`.
6. Espera hasta 30 s a que `http://localhost:4001/` responda. Si no responde, el job falla.
7. Conserva los últimos 5 releases (`KEEP_RELEASES`) y borra los más viejos.

### 11.5 Operación del día a día

```bash
# estado del servicio
launchctl print gui/$(id -u)/com.user_roles_demo | grep -E "state|pid"

# logs
tail -f ~/apps/user_roles_demo/log/stdout.log ~/apps/user_roles_demo/log/stderr.log

# reiniciar / detener
launchctl kickstart -k gui/$(id -u)/com.user_roles_demo
launchctl bootout gui/$(id -u)/com.user_roles_demo

# consola IEx conectada a la app en vivo
~/apps/user_roles_demo/current/bin/user_roles_demo remote
```

**Rollback** al release anterior (las migraciones no se revierten solas; si el release nuevo trajo una, evalúa si hace falta un `rollback` de Ecto):

```bash
cd ~/apps/user_roles_demo
ls -1t releases/                       # el primero es el actual
ln -sfn "$PWD/releases/<sha-anterior>" current
launchctl kickstart -k gui/$(id -u)/com.user_roles_demo
```

```bash
git add .github/workflows/ci.yml deploy/ rel/ lib/user_roles_demo/release.ex
git commit -m "cd: despliegue local con self-hosted runner + mix release"
git push
```

---

## 12. Siguientes pasos opcionales

- Autorización basada en `role.name` (ej. `"admin"`, `"editor"`): añade un plug que valide `Enum.any?(conn.assigns.current_user.roles, & &1.name == "admin")` y úsalo en los pipelines que lo necesiten (reutiliza `conn.assigns.current_user`, ya lo puebla `UserRolesDemoWeb.UserAuth` del paso 6).
- Si prefieres un scaffold más completo que el auth manual del paso 6 (confirmación de email, reseteo de password, "recuérdame", rate limiting) considera `mix phx.gen.auth` — ver 12.1 más abajo, porque en **este** proyecto no es un simple "correr el comando": colisiona con el `Accounts.User` que ya existe.
- Revocar tokens antes de que expiren: como son firmados (stateless) no hay tabla que borrar; si necesitas invalidación inmediata (ej. tras cambio de password), cambia `@token_salt` por usuario (ej. incluye un campo `token_version` en `User` y fírmalo como parte del salt) o migra a una tabla de tokens con `Repo.delete`.
- Filtro en la UI de Roles para ver también los inactivos (`Accounts.list_roles(include_inactive: true)`) con un toggle.
- Tests: `mix test`, y para el LiveView de usuarios, dos procesos de test simulando dos pestañas para verificar el broadcast.

### 12.1 Alternativa: `mix phx.gen.auth` (y por qué no es un simple copy/paste aquí)

```bash
mix phx.gen.auth Accounts User users
```

En Phoenix 1.8 (la versión de este proyecto) este generador creó un contexto (`Accounts`) con **dos** schemas — `User` **y** `UserToken` — más LiveViews/Controllers de registro, login, confirmación de email, "olvidé mi password" y ajustes de cuenta, y las migraciones correspondientes. Lo que cambió respecto a versiones previas de Phoenix (vale la pena saberlo antes de decidir si migrar):

- **Scopes.** Por default genera un *scope* (concepto nuevo en 1.8, ver la guía `scopes.md`) llamado como el schema (`:user`), que viaja como `conn.assigns.current_scope` / `socket.assigns.current_scope` — **no** como `current_user` directo. Es decir, en vez de `conn.assigns.current_user` (que es lo que usa `UserAuth` en este proyecto, paso 6.5) tendrías `conn.assigns.current_scope.user`. Se puede renombrar con `--scope` y `--assign-key`.
- **Login mixto: magic link + password.** El flujo generado asume login por *magic link* (un email con un enlace de un solo uso) y, opcionalmente, por password. Si permites registro con password, Phoenix **exige** que el usuario esté logueado al confirmar su cuenta — si no, es vulnerable a un ataque de *credential pre-stuffing* (alguien registra la cuenta con tu email y una password suya antes que tú, y la mantiene aunque tú tengas acceso por magic link). El generador ya implementa esta defensa (revoca tokens al confirmar, y falla si hay password puesto por otra persona), pero es una superficie de seguridad nueva que no existe en nuestro login simple de password + `Phoenix.Token` del paso 6.
- **Hash de password configurable:** `--hashing-lib bcrypt|pbkdf2|argon2` (default `bcrypt` en Unix, que es lo que ya usamos en el paso 6.1; `argon2` es más robusto pero más pesado en CPU/memoria).
- **`--live` / `--no-live`:** vistas de auth como LiveView o como controllers clásicos; si no pasás ninguna, el comando pregunta de forma interactiva.
- Otras opciones útiles: `--table` (nombre de tabla, default es el plural que pasaste), `--binary-id` (PKs/FKs como UUID), y podés invocarlo **varias veces** para recursos distintos (ej. `mix phx.gen.auth Store User users` y `mix phx.gen.auth Backoffice Admin admins`), aunque Phoenix avisa que vas a tener que resolver a mano el choque de ambos scopes intentando asignarse como `current_scope` en el mismo pipeline.

**Por qué no alcanza con correrlo tal cual en este proyecto:** ya tenemos un contexto `Accounts` y un schema `Accounts.User` con campos propios (`password` virtual, `hashed_password`, `many_to_many :roles`) y una tabla `users` ya migrada. El generador asume que el schema/tabla **no existen todavía** — crea su propia migración para `users` (con columnas como `confirmed_at`, `authenticated_at`, `hashed_password`, etc.) y una tabla nueva `users_tokens`, y no sabe nada de `roles`. Corriéndolo ahora vas a terminar con dos definiciones de `User` peleando por el mismo módulo, o una migración que choca con la que ya tenés. Dos caminos razonables:

1. **Proyecto nuevo:** corré `mix phx.gen.auth` *antes* de escribir tu propio contexto `Accounts`/`User` (osea, como primer paso, antes de la sección 4 de esta guía) y después agregás tus campos/asociaciones (como `roles`) sobre el `User` ya generado.
2. **Este proyecto (ya con `User` y `UserAuth` propios):** no lo corras directo. En su lugar, generálo aparte en un proyecto Phoenix 1.8 descartable (`mix phx.new tmp_auth --live && cd tmp_auth && mix phx.gen.auth Accounts User users`) para ver el código real que produce, y copiá a mano solo las piezas que te interesan (ej. `UserNotifier` + plantillas de email, el flujo de "olvidé mi password", la migración de `confirmed_at`) adaptándolas para que convivan con el `Accounts.User` y el `UserAuth` que ya tenés, en vez de reemplazarlos. Si además adoptás el concepto de *scope*, vas a tener que decidir si migrás `conn.assigns.current_user` → `conn.assigns.current_scope.user` en todo el proyecto (rutas, plugs, templates) o si mantenés `current_user` y simplemente ignorás los scopes.

---

## 13. Calidad de código: Credo (lint) + Dialyzer (análisis estático de tipos)

### 13.0 Qué son y por qué

- **[Credo](https://hex.pm/packages/credo)** es un linter: revisa estilo, legibilidad y señales de diseño (módulos sin `@moduledoc`, funciones muy largas, TODOs olvidados, etc.). Corre en segundos, sin compilar tipos.
- **[Dialyzer](https://www.erlang.org/doc/apps/dialyzer/dialyzer.html)** (vía **[dialyxir](https://hex.pm/packages/dialyxir)**, que le da una interfaz `mix`) hace análisis estático de tipos sobre el BEAM: detecta funciones que nunca podrían recibir el tipo que reciben, `case`/`cond` con cláusulas inalcanzables, specs `@spec` que no coinciden con la implementación, etc. Es más lento (su primera corrida construye una base de conocimiento llamada **PLT**, *Persistent Lookup Table*, con los tipos de Erlang/OTP y de tus dependencias) pero atrapa una clase de bugs que ni el compilador ni los tests cubren.
- Ambos son dependencias de **desarrollo/test únicamente** (`only: [:dev, :test], runtime: false`): no se compilan ni se incluyen en un release de producción.

### 13.1 Agregar las dependencias

```elixir
# mix.exs
defp deps do
  [
    # ...
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

```bash
mix deps.get
```

### 13.2 Credo: config y primera corrida

```bash
mix credo.gen.config   # crea .credo.exs con los checks por default (puedes ajustarlos ahí)
mix credo              # corrida normal
mix credo --strict     # incluye también los checks de severidad baja ("suggestions")
```

`mix credo explain lib/mi_archivo.ex:10:5` explica un hallazgo puntual citando el archivo/línea que reportó `mix credo`.

> Primera corrida esperable en este proyecto: va a señalar cosas como módulos sin `@moduledoc`, alias no ordenados alfabéticamente, o un TODO en un comentario — son *sugerencias* de estilo, no errores; decide cuáles vale la pena corregir y cuáles ignorar (podés desactivar checks puntuales en `.credo.exs`).

### 13.3 Dialyzer: configurar el PLT y primera corrida

Agrega la clave `:dialyzer` en `project/0` de `mix.exs` para fijar dónde vive el PLT (si no lo fijas, dialyxir usa una ruta dentro de `_build`, que se recalcula cada vez que cambias de versión de Elixir/OTP):

```elixir
# mix.exs
def project do
  [
    # ...
    dialyzer: [
      plt_add_apps: [:ex_unit, :mix],
      plt_core_path: "priv/plts",
      plt_local_path: "priv/plts"
    ]
  ]
end
```

Ignora esa carpeta en git (los PLT pesan varios MB y se regeneran solos):

```bash
# .gitignore
echo "/priv/plts/" >> .gitignore
```

Primera corrida (construye el PLT con los tipos de Erlang/OTP + Elixir + tus deps — puede tardar varios minutos la primera vez; las siguientes son incrementales y mucho más rápidas):

```bash
mix dialyzer
```

> Si solo quieres construir/actualizar el PLT sin correr el análisis todavía, usa `mix dialyzer --plt`.

### 13.4 Opcional: integrarlos a `mix precommit` o al CI

El alias `precommit` del paso 3.1 (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`) **no** incluye Credo ni Dialyzer todavía — agrégalos ahí solo si estás de acuerdo con que cada `mix precommit` tarde más (Dialyzer en particular, aun con PLT ya construido, agrega varios segundos):

```elixir
# mix.exs
precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "credo --strict", "test"]
```

Dialyzer normalmente se deja fuera de `precommit` (es lento incluso con el PLT cacheado) y se agrega como paso aparte en CI (paso 10.1), después de `mix format --check-formatted` y antes de `mix test`:

```yaml
# .github/workflows/ci.yml
- name: Lint con Credo
  run: mix credo --strict

- name: Restaurar PLT de Dialyzer
  uses: actions/cache@v4
  with:
    path: priv/plts
    key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}

- name: Análisis estático con Dialyzer
  run: mix dialyzer
```

> Cachear `priv/plts` en CI (como arriba) es importante: sin caché, cada corrida de CI reconstruiría el PLT completo desde cero, agregando varios minutos a cada push/PR.

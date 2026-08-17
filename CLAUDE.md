# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

DaleApp is a Phoenix 1.8 / LiveView web app (Elixir ~> 1.15). It's a loyalty/rewards platform connecting brands ("marcas") with consumers: brands manage stores, staff, inventory, and points-based rewards; customers browse products, follow brands, chat, and redeem coupons/prizes. **The domain and UI are entirely in Spanish** — schema fields, route paths, module names, and templates all use Spanish terms (e.g. `Marcas`/brands, `Productos`/products, `Ventas`/sales, `Sedes`/store locations, `Cajeros`/cashiers, `Bitacora`/log, `Canjes`/redemptions).

## Commands

- `mix setup` — install deps, create/migrate DB, build assets
- `mix phx.server` / `iex -S mix phx.server` — run the dev server (localhost:4000)
- `mix test` — run tests (auto-creates/migrates the test DB via the `test` alias)
- `mix test test/path/to_test.exs` — run a single test file
- `mix test test/path/to_test.exs:42` — run a single test at a line
- `mix test --failed` — re-run only previously failed tests
- `mix precommit` — **run this after finishing any change**: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`
- `mix ecto.gen.migration migration_name_using_underscores` — always use this to create migrations (correct timestamp/conventions)
- `mix help <task>` — check docs/options before using an unfamiliar mix task

## Architecture

### Contexts (`lib/dale_app/`)
Standard Phoenix contexts, each a `*.ex` file plus a same-named subdirectory of schemas:
- `Accounts` — users, roles (`RolEmpleado`), staff-to-location assignment (`EmpleadoSede`), attendance (`Asistencia`, `BajaEmpleado`), push subscriptions
- `Brands` — `Brand`, `BrandLocation` (sedes), work schedules (`HorarioTrabajo`)
- `Products` — the largest context: `Product`, stock (`StockItem`, `MovimientoStock`, `IncidenciaStock`), sales (`Venta`), rewards (`Premio`, `Canje`), custom categories/sizes, rotation alerts, sell-through snapshots
- `Claims`, `Coupons`, `Comentarios`, `Likes`, `Favorites`, `Friends`, `Mensajes` (chat), `Publicaciones` (posts/feed), `Events`, `MapSaves` — smaller social/marketing features
- Cross-cutting: `Storage` (Cloudinary image upload/delete via `Req`), `Cloudflare` (config only, `config :dale_app, :cloudflare`), `Mailer` (Swoosh)

### Web layer (`lib/dale_app_web/`)
- Mix of Phoenix controllers (`*_controller.ex` + `*_html/*.html.heex` templates) and LiveViews (`live/*_live.ex`) — LiveView is used for the more interactive brand-management screens (`/mi-tienda/*`: cajeros, ventas, stock, sedes, asistencia), controllers handle the rest
- Single router pipeline (`browser`) for the whole app — no `api` routes are actually used, and there is **no `live_session`/`on_mount` auth pattern**. Auth is a plain `DaleAppWeb.Plugs.SetCurrentUser` plug that reads `user_id` from the session and assigns `current_user` on the conn; LiveViews independently re-read `session["user_id"]` in `mount/3` and load the current brand/user themselves. **This project does not use Phoenix 1.8's `current_scope` convention** — despite AGENTS.md's generic Phoenix 1.8 guidance mentioning it, follow the existing `current_user`/session pattern instead
- Auth providers: Ueberauth with Google and Discord OAuth (`AuthController`), plus `bcrypt_elixir` for password handling
- Route paths and controller/LiveView names are Spanish (e.g. `/mi-tienda/stock/bitacora` → `BitacoraLive`, `/cajero/scanear` → `ClaimController.redeem`)

### External integrations
- **Cloudinary** (`DaleApp.Storage`) for image upload/delete — signs requests manually with `CLOUDINARY_*` env vars
- **Cloudflare** — configured via `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` in `config/runtime.exs`
- **Web Push** (`web_push_elixir`) for browser push notifications, VAPID keys from env
- QR/barcode generation via `eqrcode` and `barlix` (used for coupon/claim scanning flows)
- HTTP client is always `Req` — never add `httpoison`/`tesla`/`httpc`

### Repo conventions
- Untracked `*.backup*`/`.backup-*` files scattered through `lib/` are the user's local scratch copies (see `.gitignore`'s "Backups locales" section) — not part of the tracked codebase, ignore them unless the user references one directly
- Commit messages in this repo are typically Spanish "Checkpoint" messages describing the state before a change, not conventional-commit style — match existing style unless told otherwise

## Coding guidelines

This repo ships an `AGENTS.md` with the standard Phoenix/Elixir/Ecto/LiveView usage rules (HEEx syntax, streams, forms, changesets, etc.) generated for this project — **read it** for the detailed dos and don'ts. Key points not obvious from AGENTS.md alone:
- The `current_scope` guidance in AGENTS.md does not apply here (see Auth note above) — this app was not generated with `mix phx.gen.auth`'s scope system
- Test coverage is currently minimal (only `error_html`, `error_json`, `page_controller` tests exist) — there's no established pattern yet for testing LiveViews or contexts in this repo, so use the general Phoenix/LiveView test guidelines from AGENTS.md when adding tests

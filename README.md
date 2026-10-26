# ResQ Dispatch - Emergency Vehicle Dispatch System

**Problem statement:** Use a priority queue to arrange emergency service requests according to urgency.

ResQ Dispatch is a Data Structures project that simulates an ambulance dispatch centre.
Incoming emergencies are stored in a **priority queue (binary min-heap)** so the most urgent
request is always served first, and **Dijkstra's shortest-path algorithm** picks the nearest
suitable ambulance on a road graph of Pune.

## Data structures and algorithms used

| Concept | Where | Why |
|---|---|---|
| Priority queue (indexed binary min-heap) | `src/pqueue.hpp` | Orders requests by (priority, arrival). High > Medium > Low, FIFO within a level. push/pop O(log n), peek O(1), remove-by-id O(log n) |
| Hash map (position index) | `src/pqueue.hpp` | Tracks each request's heap index so a specific request can be dispatched/removed in O(log n) |
| Graph (adjacency list) + Dijkstra | `src/graph.hpp` | Shortest road distance from the emergency to every available ambulance |
| Relational tables (SQLite) | `db/schema.sql` | Persists users, emergencies, fleet and dispatch history |

## Live demo

The repo deploys to Vercel as-is: `vercel.json` serves the standalone demo at `/`
(login `admin` / `ResQ@123`). Only the frontend demo is hosted; the C++ backend runs locally.

## Deploying the full stack (Render)

The backend serves the full UI too, so one Docker service is the whole app.
`Dockerfile` builds the server with Crow + SQLite on Ubuntu and runs the tests during the build;
`render.yaml` describes a free Render web service. On Render: **New > Blueprint**, pick this repo, apply.
The server reads the `PORT` variable the host provides. On the free plan the service sleeps after
~15 idle minutes (first request then takes ~1 minute) and the SQLite file resets on every restart
back to the demo data.

## Two ways to run

1. **Quick demo (no install):** open `demo/ResQ_Dispatch_Standalone.html` in any browser.
   A frontend-only version that stores data in the browser (`localStorage`) and orders the
   queue by sorting. Login: `admin` / `ResQ@123`.
2. **Full stack (C++ backend + SQLite):** build and run as described in section 1 below,
   then open http://localhost:8080. This version uses the real heap and Dijkstra.

## Project structure

```
ResQ-Dispatch/
  demo/ResQ_Dispatch_Standalone.html   frontend-only demo (open directly in a browser)
  CMakeLists.txt, vcpkg.json     build files (dependencies: Crow, SQLite3)
  CMakePresets.json, .vscode/    VS Code build/run/debug setup
  setup.bat build.bat run.bat test.bat   Windows helpers
  db/schema.sql                  tables
  db/seed.sql                    road graph for Dijkstra (nodes + edges)
  db/demo_data.sql               demo fleet + 4 sample emergencies (also used by "Reset Records")
  src/main.cpp                   Crow HTTP layer: routes only
  src/service.hpp                all business logic (auth, notifications, queue, dispatch, vehicles)
  src/pqueue.hpp                 priority queue (indexed binary heap)
  src/graph.hpp                  road graph + Dijkstra's algorithm
  src/paths.hpp                  finds the project folder from any start location
  src/crypto.hpp                 SHA-256, HMAC, PBKDF2 password hashing, secure random
  src/db.hpp, src/jsonw.hpp      SQLite wrapper, JSON writer
  public/index.html, app.js      full-stack frontend (served by the backend)
  tests/                         automated tests
```

## 1. Build and run on Windows (VS Code)

**Install once:** [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/downloads/) (or Community)
with the **"Desktop development with C++"** workload, [CMake](https://cmake.org/download/) (3.21+),
[Git](https://git-scm.com/download/win), and VS Code with the **C/C++** and **CMake Tools** extensions
(VS Code will offer them when you open the folder).

**Then:**

1. Extract the zip, then in VS Code: **File > Open Folder...** and choose the extracted folder
   (the one that contains `CMakeLists.txt`).
2. Press **Ctrl+Shift+B** (task *ResQ: Build (Release)*). The first run installs vcpkg to `C:\vcpkg` if it
   is missing, then downloads and compiles Crow + SQLite - allow **5-10 minutes**. Later builds take seconds.
3. **Terminal > Run Task... > ResQ: Run server**, then open **http://localhost:8080**.
4. Sign in with `admin` / `ResQ@123`.

Prefer the command line? In the project folder run `build.bat`, then `run.bat`
(`test.bat` runs the automated tests; `setup.bat` only installs vcpkg).
Debugging: **F5** (*ResQ: Debug server*) builds a Debug version and starts it under the debugger.

Notes:
- Do not open `index.html` by double-clicking; the page must be served by the backend.
- The server finds its `db/` and `public/` folders by itself, so it works from any start folder.
- The database file `resq.db` is created next to `CMakeLists.txt` on first start. To start from
  scratch, stop the server and delete `resq.db*`.
- If setup.bat just installed vcpkg while VS Code was open, close and reopen VS Code once.
- If port 8080 is busy: `set RESQ_PORT=8081` before `run.bat`, and open that port instead.

**Default login:** username `admin`, password `ResQ@123`.
Change it before showing the project to anyone: `set RESQ_ADMIN_PASSWORD=YourNewPassword` *before the
very first start* (the password is only applied when the admin account is first created), or later
through `PUT /api/profile/password`.

| Environment variable | Default | Meaning |
|---|---|---|
| `RESQ_PORT` | `PORT`, else `8080` | HTTP port |
| `RESQ_BIND` | `127.0.0.1` | Address to listen on (localhost only; `0.0.0.0` exposes it to the network) |
| `RESQ_DB` | `<project>/resq.db` | SQLite file |
| `RESQ_ADMIN_PASSWORD` | `ResQ@123` | Password for the first-created `admin` account |
| `RESQ_ROOT` | auto-detected | Folder containing `db/` and `public/` |

## 2. What the backend does

**Accounts and roles.** Two roles: `admin` (seeded) and `dispatcher` (everyone who signs up).
Passwords are stored as salted PBKDF2-HMAC-SHA256 (100,000 iterations); a login returns a random
bearer token, valid 12 hours, of which only the SHA-256 hash is stored. Five wrong passwords for the
same username lock that username for 60 seconds. Only admins can reset records, manage vehicles and
list users.

**Notifications.** Stored per user. New emergencies, dispatches, completed trips, vehicle changes and
profile edits create notifications for the relevant users. *Mark all as read* and *Clear all* are
server-side (`POST /api/notifications/read-all`, `DELETE /api/notifications`), so they survive a
refresh or a new login.

**Priority queue.** Waiting emergencies live in an in-memory binary min-heap ordered by
(priority, arrival id): High before Medium before Low, oldest first within a level. Insert and
remove are O(log n), peek is O(1). The heap is rebuilt from the database on start-up. The UI shows
the order the server computes.

**Dijkstra.** `db/seed.sql` defines 11 Pune locations and the road distances between them. The
emergency's free-text location (e.g. "MG Road, Pune") is matched to a node by name/alias. One
Dijkstra run from that node gives the distance to every available ambulance; the nearest *suitable*
one is chosen (ties go to the lower id). Suitability: *Cardiac Arrest* and *Breathing Issue* need an
**ALS** unit; every other type accepts ALS or BLS. If no suitable unit is free the dispatch is
refused (HTTP 409) instead of silently sending the wrong unit. If the location is not on the graph,
the first suitable unit is used and the response says so (`method: "fallback"`, no distance).
The distances in `seed.sql` are **rough illustrative values, not surveyed road distances** - edit the
`edges` table to change them (restart the server to reload).

Manual **Assign** on a specific ambulance still works as before; if that unit is unsuitable it is
allowed but the response contains a warning that the dispatch panel displays.

## 3. API reference

All endpoints return JSON. Errors look like `{"error":"message"}`. Except login, signup and health,
send `Authorization: Bearer <token>`.

| Method and path | Role | Body / notes |
|---|---|---|
| `POST /api/auth/login` | public | `{username, password}` (username or email) -> `{token, user}` |
| `POST /api/auth/signup` | public | `{name, username, email, password}` -> 201 `{token, user}` (role `dispatcher`) |
| `POST /api/auth/logout` | any | revokes the token |
| `GET /api/auth/me` | any | `{user}` |
| `PUT /api/profile` | any | `{name, email}` (email may be empty) |
| `PUT /api/profile/password` | any | `{currentPassword, newPassword}`; revokes all your sessions |
| `GET /api/notifications` | any | `{notifications:[...], unread}` (latest 30) |
| `POST /api/notifications/read-all` | any | marks all of your notifications read |
| `DELETE /api/notifications` | any | clears all of your notifications |
| `GET /api/state` | any | emergencies, fleet, history, `queue` (ids in dispatch order), `stats` |
| `POST /api/emergencies` | any | `{type, priority, location, patient, details}` -> 201 with `queuePosition` |
| `GET /api/emergencies/{id}/nearest` | any | preview which vehicle Dijkstra would pick (changes nothing) |
| `POST /api/dispatch` | any | `{requestId?, ambulanceId?}`; none = top of the queue + Dijkstra |
| `POST /api/dispatches/{id}/complete` | any | finishes a trip; the ambulance becomes Available at City Centre |
| `GET /api/vehicles` | any | list |
| `POST /api/vehicles` | admin | `{id, type: "ALS"/"BLS", location}` |
| `PUT /api/vehicles/{id}` | admin | any of `{type, location, status}`; status is Available, On Duty or Maintenance |
| `DELETE /api/vehicles/{id}` | admin | refused while on a trip or if it has dispatch history |
| `POST /api/admin/reset` | admin | restores the demo fleet/emergencies, clears dispatch history |
| `GET /api/users` | admin | account list (no password data) |
| `GET /api/health` | public | `{ok:true}` |

Typical status codes: 400 invalid input, 401 not signed in / wrong password, 403 not allowed for
your role, 404 not found, 409 conflict (e.g. no available ambulance, already dispatched),
429 too many failed logins.

## 4. Frontend: standalone vs full stack

- `demo/ResQ_Dispatch_Standalone.html` is the original single-file frontend: all data lives in the
  browser's `localStorage`, and the queue order is computed by sorting the waiting list.
- `public/index.html` keeps the same HTML/CSS; the inline script is moved to `public/app.js`, where
  storage calls became REST API calls to the C++ backend. The hard-coded password and the browser-side
  account list are removed.
- Full-stack additions: unit type shown in the fleet list (`· ALS`), distance and route in the dispatch
  panel, real timestamps, and auto-refresh every 5 seconds so two dispatchers see each other's changes.
- *Reset Records* is admin-only; automatic dispatch applies the ALS rule; "Dispatched Today" starts
  from a baseline of 28 stored in the `meta` table (key `dispatched_baseline`; set it to `0` for a real count).
- Unchanged static text: the "DSA Concepts" page, the "Avg Response Time 3.5" card, and the notes
  saying data lives "in this browser session".

## 5. Test status

Verified on Linux (g++ 13, SQLite 3.45):

| Area | How it was checked | Result |
|---|---|---|
| SHA-256, HMAC, PBKDF2, hex, random | known-answer vectors (FIPS 180, RFC 4231, RFC 7914) | pass |
| Priority queue | unit tests + 500-step randomised comparison with a sorted list | pass |
| Dijkstra | textbook graph, unreachable and unknown nodes | pass |
| Service layer on real SQLite (auth, lockout, profile, notifications, queue, dispatch, Dijkstra choices, ALS rule, vehicles, roles, reset, restart persistence) | `tests/test_service.cpp`, 162 checks | pass |
| `public/app.js` against the real service | Node with a stub DOM + a harness calling the C++ service, 60 checks | pass |
| `src/main.cpp` start-up path and route signatures | compiled warning-free against a stand-in `crow.h` and run on real SQLite | pass |

**Not yet verified:** the build with the real Crow library through CMake/vcpkg/Visual Studio on
Windows, and the UI in a real browser against the running server.

## 6. Known limits

- Plain HTTP on localhost - fine for a college demo; put it behind HTTPS before any real use.
- The password hashing is hand-written (tested against the official vectors) to avoid extra
  dependencies; a production system should use a vetted library such as libsodium or bcrypt.
- One SQLite connection guarded by one mutex: ample for a demo, not for heavy load.
- Road distances are illustrative; this is a simulation and contacts no real ambulance or service.

## Quick orientation for AI coding agents

This repository is a Flutter mobile app (lib/) with a small Node-based backend proof-of-concept (backend/). The mobile app uses Riverpod for state, GoRouter for navigation, and an in-memory repository layer by default. The video upload pipeline is central: clients request upload sessions, PUT directly to S3 (or a local POC server), then poll for job readiness.

Keep these facts front-and-center when making edits or suggestions:

- Entry points
  - `lib/main.dart` — loads `assets/config/backend_config.json` and bootstraps `ProviderScope` with `backendConfigProvider`.
  - `lib/app.dart` — wires `GoRouter`, theme, and top-level services.

- State & routing conventions
  - Riverpod (flutter_riverpod) is used across the app. Look for `Provider`/`ProviderScope`/`ConsumerWidget` patterns.
  - Navigation is configured via `lib/core/routing/app_router.dart` (GoRouter). Updates to routes should keep router providers intact.

- Video pipeline (most important domain)
  - Runtime config: `assets/config/backend_config.json` controls the backend base URL. During local dev this points to `http://10.0.2.2:3001/api/` (see README).
  - Client orchestration lives in `lib/core/video/upload/video_upload_repository.dart` (session creation, S3 uploads, finalize + polling).
  - Toggle/choice for upload provider: see `lib/features/video/services/mux_upload_service.dart` and flags like `kUseMux` mentioned in README.
  - Backend POC: `backend/server` is an Express server that mimics presigned URLs and ffmpeg processing — useful to run locally when testing the UI without cloud infra.

- Local dev & build workflows (common tasks)
  - Fetch deps: `flutter pub get`.
  - First-time platform scaffolding: run `flutter create .` from the project root if native folders are missing.
  - Run app: `flutter run` (or `flutter run -d <device-id>`). Hot reload: `r` / hot restart: `R` in the runner console.
  - Run tests: `flutter test`. Unit and widget tests are under `test/`.
  - Backend POC: `cd backend/server && npm install && npm run dev` (requires ffmpeg on PATH).

- Project-specific conventions you should follow or be aware of
  - Many repositories use in-memory sample data under `lib/core/constants/sample_data.dart`. When changing data shape, update both the samples and repository interfaces.
  - Admin functionality is gated by the auth state and a UI toggle; admin edits commonly update in-memory repositories and emit stream events. Check `lib/features/admin/` and auth providers for expectations.
  - Assets used for runtime wiring (backend_config.json) are declared in `pubspec.yaml`. When changing those files, ensure `flutter pub get` and a restart so the app reloads them.
  - Linting & style follow `analysis_options.yaml` and `flutter_lints`. Prefer minimal, targeted edits to keep diffs reviewable.

- Integration points & external dependencies
  - External services considered in code: Mux, AWS S3/MediaConvert/CloudFront (backend infra under `backend/infrastructure`), and Mux webhooks (backend/server listens for these in POC).
  - Secrets and credentials are NOT in the repo. Where necessary, read/write environment variables for local servers and document the expected variables (see `backend/server` and README).

- Where to look for quick examples/tests
  - Video flow wiring: `lib/features/video/` (models, services, widgets). `lib/features/video/models/video_timeline.dart` contains timeline/edit model code.
  - API + POC server: `backend/server/server.js` (routes: `/api/videos/sessions`, `/api/videos/:jobId`, webhooks).
  - Infrastructure samples and expected responses: `backend/reference/api-responses/` and `backend/reference/samples/`.

Small rules for agent edits

- When changing the video upload flow, update both the Flutter client (`lib/core/video/upload/...`) and the POC backend (`backend/server`) or document why the POC can remain unchanged.
- Avoid hardcoding backend hostnames. Use `assets/config/backend_config.json` and the `backendConfigProvider` established in `lib/main.dart`.
- If you modify public APIs (endpoints/response shapes), update `backend/reference/api-responses/` and add or update a test in `test/` showing the new shape.
- Preserve existing Provider/Router wiring: refactor providers but keep original override patterns in `main.dart` to avoid boot-time regressions.

If anything here is unclear or you'd like the notes to dig deeper (for example, trace providers for a specific feature or list the most-used providers), tell me which area to expand and I will iterate.

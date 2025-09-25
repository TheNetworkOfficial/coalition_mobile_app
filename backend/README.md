# Video Upload Backend

This directory houses the source-of-truth for the AWS video upload pipeline that powers the mobile application. The backend receives upload signing requests, returns pre-signed S3 URLs, and serves the resulting media via CloudFront.

## Architecture
- **Amazon S3** (`lux-video-dev-262a61d7` – region `us-west-2`)
  - Objects live under the `videos/` prefix and automatically expire after 30 days.
  - CORS allows `GET`, `HEAD`, `PUT` from any origin and exposes the `ETag` header.
- **AWS Lambda** (`lux-sign-uploads`, Node.js 20)
  - Returns pre-signed PUT URLs for each upload path.
  - Environment variables: `BUCKET`, `PREFIX`, `PUBLIC_BASE_URL`.
  - Scoped execution role (`lux-sign-uploads-role`) permits `s3:PutObject` on the bucket only.
- **Amazon API Gateway** (`lux-video-api` HTTP API)
  - Single `POST /` route integrated with the Lambda function.
  - CORS allows `POST`/`OPTIONS` with `content-type` and `authorization` headers.
  - HTTP APIs do **not** support API keys, so plan on securing the endpoint with JWT/OAuth authorizers if authentication is required.
- **Amazon CloudFront** (`d21wy4swosisq5.cloudfront.net`)
  - Origin Access Control to S3, custom cache policies for manifests and segments, and a response headers policy that injects CORS/ETag headers.

## Repository Layout
- `functions/sign-uploads/` – Lambda implementation plus packaging artifacts.
- `infrastructure/`
  - `api-gateway/` – exported API configuration.
  - `cloudfront/` – cache policies, response headers, and distribution configurations.
  - `iam/` – trust and permissions policies for the signer role.
  - `s3/` – lifecycle and CORS configuration for the bucket.
- `server/` – local proof-of-concept processor (Express + ffmpeg) used for emulator testing.
- `reference/` – sample Lambda/API responses and placeholder media files used during verification.

## Deployment Workflow
1. **Prepare the Lambda package**
   - See `functions/sign-uploads/README.md` for install/zip instructions.
   - Upload the resulting archive and publish a new Lambda version.
2. **Provision/Update Infrastructure**
   - Apply the bucket CORS, lifecycle, and bucket policy JSON files.
   - Attach the IAM trust and inline policy to the Lambda execution role.
   - Update the API Gateway integration if the Lambda ARN changes.
   - Apply the CloudFront cache policy IDs and distribution configuration (`distribution/final-config.json`).
3. **Verify**
   - Use the sample payload in `reference/api-responses/signer-success.json` to request pre-signed URLs.
   - Upload placeholder assets (see `reference/samples/`) and confirm playback via CloudFront.

## Local Proof of Concept Server

The `server/` folder contains an Express-based processor that keeps the Flutter client lightweight by moving transcoding off-device during development:

```bash
cd backend/server
npm install
npm run dev
```

Requirements:

- ffmpeg available on your PATH (`ffmpeg -version`)
- ffprobe available on your PATH (`ffprobe -version`)
- Disk write access under `backend/server/uploads/` and `backend/server/media/`

How it works:

1. The client posts raw videos to `POST /api/videos`.
2. The server stores the upload, runs ffmpeg/ffprobe to create MP4 renditions plus an HLS package, and serves them from `/media/<jobId>/`.
3. Job status is tracked in-memory and exposed via `GET /api/videos/:jobId`.
4. Flutter polls this endpoint until the job is `ready`, then switches playback to the served manifest.

This proof-of-concept mirrors the eventual AWS pipeline (Lambda + S3 + MediaConvert) but avoids cloud round-trips while you iterate on the UX.

## Monitoring & Observability
- Configure CloudWatch metric filters for Lambda errors and 4xx/5xx responses from API Gateway so alerting fires when signing fails.
- Enable CloudFront logging to an S3 bucket and wire an Athena table/dashboard to watch cache-hit ratios, latency, and segment download errors.
- Add S3 access logs (or CloudTrail data events) for the media bucket to audit unexpected uploads or deletions.
- Consider a periodic health check that exercises the signer endpoint and publishes custom metrics (success/latency) for quick detection of regressions.

## Storage Hygiene
- Derived renditions and HLS segments are deleted locally after a successful upload; the S3 lifecycle policy expires remote media after 30 days.
- Keep the Lambda execution role limited to `s3:PutObject` on the bucket and avoid embedding long-lived credentials in client apps.
- If users re-upload with the same `jobId`, issue a CloudFront invalidation for the affected prefix to flush stale manifests/segments.

## Flutter Integration Touchpoints
- `assets/config/cdn_config.json` defines the signer endpoint and CDN base URL consumed by the app.
- `lib/services/video_uploader.dart` and `lib/core/video/cdn/video_cdn_service.dart` call the API Gateway endpoint and upload media using the pre-signed URLs.

Keep environment secrets (AWS credentials, auth tokens) outside of version control. The JSON files here are sanitized outputs intended as documentation/inputs for future infrastructure-as-code automation.

# sign-uploads Lambda

This Lambda issues presigned `PUT` URLs that allow the transcoder to push HLS manifests and MP4 renditions into the `lux-video-dev-262a61d7` bucket under the `videos/` prefix.

## Runtime Configuration
Set the following environment variables when deploying the function:

| Key | Description |
| --- | --- |
| `BUCKET` | Destination bucket name (`lux-video-dev-262a61d7`). |
| `PREFIX` | Top-level folder for uploads (default `videos`). |
| `PUBLIC_BASE_URL` | CloudFront domain used by the mobile app (`https://d21wy4swosisq5.cloudfront.net`). |

## Packaging Steps
1. Install production dependencies:
   ```bash
   npm ci --omit=dev
   ```
2. Create the deployment archive:
   ```bash
   npm run zip
   ```
   The zipped bundle is written to `dist/sign-uploads.zip`.
3. Deploy the archive via the AWS Console or CLI (`aws lambda update-function-code ...`).
4. (Optional) Clean up local artifacts to keep the repo lean:
   ```bash
   rm -rf node_modules dist
   ```

## Invocation Contract
Expected request body
```json
{
  "jobId": "<unique-id>",
  "files": [
    { "path": "hls/master.m3u8", "contentType": "application/vnd.apple.mpegurl" },
    { "path": "mp4/720.mp4", "contentType": "video/mp4" }
  ]
}
```
Response payload mirrors the capture in `../../reference/api-responses/signer-success.json`.

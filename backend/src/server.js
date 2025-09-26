import 'dotenv/config';
import express from 'express';
import bodyParser from 'body-parser';
import muxPkg from '@mux/mux-node';
import * as db from './db.js';
const { Mux, Webhooks } = muxPkg;

const app = express();

// JSON for normal routes:
app.use('/api', bodyParser.json());

// RAW body for webhook signature verification:
app.use('/webhooks/mux', bodyParser.raw({ type: '*/*' }));

// CORS (narrow if you know your origins)
const ALLOWED = process.env.ALLOWED_CORS_ORIGIN || '*';
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', ALLOWED);
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

// Mux client (reads MUX_TOKEN_ID/SECRET from env automatically)
const mux = new Mux();

// --- 1) Create Direct Upload URL ---
// POST /api/mux/direct-uploads
app.post('/api/mux/direct-uploads', async (req, res) => {
  try {
    const { filename, filesize, content_type = 'video/mp4', cors_origin } = req.body || {};

    // (Optional) create your own application-side ID and store it to map later
    // e.g., const draftPostId = await db.createDraft({ filename, filesize, content_type })

    const upload = await mux.video.uploads.create({
      cors_origin: cors_origin || process.env.ALLOWED_CORS_ORIGIN || '*',
      new_asset_settings: {
        // Use passthrough to tie the future Asset/webhooks back to your app record:
        // passthrough: draftPostId,
        playback_policy: ['public'],
        video_quality: 'basic'
      }
    });

    // Respond with what the mobile app needs
    return res.status(201).json({
      upload_id: upload.id,
      url: upload.url,     // client will PUT the file to this URL
      method: 'PUT'
    });
  } catch (err) {
    console.error('Mux upload create error', err);
    return res.status(500).json({ error: 'failed_to_create_direct_upload' });
  }
});

// --- 2) (Optional) Poll upload/asset status ---
// GET /api/mux/uploads/:id
app.get('/api/mux/uploads/:id', async (req, res) => {
  try {
    const u = await mux.video.uploads.retrieve(req.params.id);
    return res.json(u);
  } catch (err) {
    return res.status(404).json({ error: 'not_found' });
  }
});

// --- 3) Webhook to finalize posts ---
// POST /webhooks/mux
app.post('/webhooks/mux', async (req, res) => {
  const signature = req.headers['mux-signature'];
  const secret = process.env.MUX_WEBHOOK_SECRET;
  if (!secret) {
    console.error('Mux webhook secret is not configured.');
    return res.sendStatus(500);
  }

  let event;
  try {
    Webhooks.verifyHeader(req.body, signature, secret);
    event = JSON.parse(req.body.toString('utf8'));
  } catch (err) {
    console.error('Invalid Mux webhook signature', err);
    return res.sendStatus(400);
  }

  try {
    const { type, data = {} } = event;

    if (type === 'video.upload.asset_created') {
      const uploadId = data.id ?? data.upload_id ?? data.source_upload_id ?? data.upload?.id;
      const updated = db.markAssetCreated({
        passthrough: data.passthrough ?? data.custom_data?.passthrough ?? null,
        assetId: data.asset_id ?? null,
        uploadId: uploadId ?? null,
      });
      if (!updated) {
        console.warn('No post found for Mux upload asset_created event', {
          uploadId,
          passthrough: data.passthrough,
        });
      }
    }

    if (type === 'video.asset.ready') {
      const uploadId = data.upload_id ?? data.source_upload_id ?? data.upload?.id;
      const playback = Array.isArray(data.playback_ids)
        ? data.playback_ids.find((id) => id.policy === 'public') ?? data.playback_ids[0]
        : null;
      const playbackId = playback?.id ?? null;
      const playbackUrl = playbackId && playback?.policy === 'public'
        ? `https://stream.mux.com/${playbackId}.m3u8`
        : null;
      const duration = typeof data.duration === 'number' ? data.duration : null;
      const aspectRatio = typeof data.aspect_ratio === 'string' ? data.aspect_ratio : null;

      const finalized = db.finalizePost({
        passthrough: data.passthrough ?? data.custom_data?.passthrough ?? null,
        playbackId,
        playbackUrl,
        duration,
        aspectRatio,
        assetId: data.id ?? null,
        uploadId: uploadId ?? null,
      });
      if (!finalized) {
        console.warn('No post found for Mux asset_ready event', {
          assetId: data.id,
          uploadId,
          passthrough: data.passthrough,
        });
      }
    }

    return res.sendStatus(200);
  } catch (err) {
    console.error('Webhook handling error', err);
    return res.sendStatus(500);
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Backend listening on :${port}`));

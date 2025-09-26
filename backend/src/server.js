import 'dotenv/config';
import express from 'express';
import bodyParser from 'body-parser';
import muxPkg from '@mux/mux-node';
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
  // Verify signature
  const signature = req.headers['mux-signature'];
  const secret = process.env.MUX_WEBHOOK_SECRET;
  let event;
  try {
    Webhooks.verifyHeader(req.body, signature, secret);
    event = JSON.parse(req.body.toString('utf8'));
  } catch (err) {
    console.error('Invalid Mux webhook signature', err);
    return res.sendStatus(400);
  }

  try {
    const { type, data } = event;

    if (type === 'video.upload.asset_created') {
      // data.asset_id exists; data.id is the Direct Upload id
      // If you set new_asset_settings.passthrough when creating the upload,
      // use data.passthrough to look up the draft post in your DB and attach asset_id.
      // await db.markAssetCreated({ passthrough: data.passthrough, assetId: data.asset_id });
    }

    if (type === 'video.asset.ready') {
      // Finalize your post: store playback info for the feed.
      // Typical fields:
      // - data.id (asset id)
      // - data.playback_ids[0].id  => playback_id
      // - build HLS URL: https://stream.mux.com/${playback_id}.m3u8
      // await db.finalizePost({ passthrough: data.passthrough, playbackId, assetId: data.id });
    }

    // Handle other events as needed; always 200 quickly.
    return res.sendStatus(200);
  } catch (err) {
    console.error('Webhook handling error', err);
    return res.sendStatus(500);
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Backend listening on :${port}`));

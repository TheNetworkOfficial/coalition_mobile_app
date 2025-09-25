const express = require('express');
const cors = require('cors');
const multer = require('multer');
const morgan = require('morgan');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs-extra');
const { spawn } = require('child_process');

const PORT = process.env.PORT || 3001;
const app = express();

app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

const ROOT = path.join(__dirname, '..');
const UPLOAD_ROOT = path.join(ROOT, 'uploads');
const MEDIA_ROOT = path.join(ROOT, 'media');

fs.ensureDirSync(UPLOAD_ROOT);
fs.ensureDirSync(MEDIA_ROOT);

const jobs = new Map();

app.use('/media', express.static(MEDIA_ROOT));

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const jobId = req.jobId || (req.jobId = uuidv4());
    const jobDir = path.join(UPLOAD_ROOT, jobId);
    fs.ensureDirSync(jobDir);
    cb(null, jobDir);
  },
  filename: (req, file, cb) => {
    const extension = path.extname(file.originalname) || '.bin';
    if (file.fieldname === 'video') {
      cb(null, `source${extension}`);
    } else if (file.fieldname === 'cover') {
      cb(null, `cover${extension}`);
    } else {
      cb(null, `${file.fieldname}${extension}`);
    }
  },
});

const upload = multer({ storage });

app.post(
  '/api/videos',
  upload.fields([
    { name: 'video', maxCount: 1 },
    { name: 'cover', maxCount: 1 },
  ]),
  async (req, res) => {
    if (!req.files || !req.files.video || !req.files.video.length) {
      return res.status(400).json({ error: 'A video file is required.' });
    }

    const jobId = req.jobId || uuidv4();
    const videoFile = req.files.video[0];
    const coverFile = req.files.cover ? req.files.cover[0] : null;

    const metadata = {
      description: req.body.description || '',
      hashtags: parseList(req.body.hashtags),
      mentions: parseList(req.body.mentions),
      location: req.body.location || '',
      visibility: req.body.visibility || 'public',
      allowComments: toBoolean(req.body.allowComments, true),
      allowSharing: toBoolean(req.body.allowSharing, true),
    };

    const now = new Date().toISOString();
    const job = {
      id: jobId,
      status: 'processing',
      createdAt: now,
      updatedAt: now,
      metadata,
      source: {
        path: videoFile.path,
        originalName: videoFile.originalname,
        mimeType: videoFile.mimetype,
        size: videoFile.size,
      },
      cover: coverFile
        ? {
            path: coverFile.path,
            originalName: coverFile.originalname,
            mimeType: coverFile.mimetype,
            size: coverFile.size,
          }
        : null,
      outputs: {},
      error: null,
    };

    jobs.set(jobId, job);

    processJob(job).catch((error) => {
      console.error('Failed to process job', jobId, error);
    });

    res.status(202).json({ jobId, status: job.status });
  },
);

app.get('/api/videos/:jobId', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  res.json(serializeJob(job));
});

app.get('/api/videos', (req, res) => {
  const payload = Array.from(jobs.values()).map(serializeJob);
  res.json({ jobs: payload });
});

app.listen(PORT, () => {
  console.log(`Video processing server running on http://localhost:${PORT}`);
});

function serializeJob(job) {
  return {
    id: job.id,
    status: job.status,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    metadata: job.metadata,
    outputs: job.outputs,
    error: job.error,
  };
}

async function processJob(job) {
  const jobMediaDir = path.join(MEDIA_ROOT, job.id);
  await fs.ensureDir(jobMediaDir);
  const inputPath = job.source.path;
  const playlistPath = path.join(jobMediaDir, 'master.m3u8');
  const segmentTemplate = path.join(jobMediaDir, 'segment_%03d.ts');
  const coverPath = path.join(jobMediaDir, 'cover.jpg');

  try {
    await createCover(job, inputPath, coverPath);
    await createHls(job, inputPath, playlistPath, segmentTemplate);

    job.outputs = {
      coverUrl: `/media/${job.id}/cover.jpg`,
      playlistUrl: `/media/${job.id}/master.m3u8`,
    };
    job.status = 'ready';
    job.error = null;
  } catch (error) {
    job.status = 'failed';
    job.error = error.message;
  } finally {
    job.updatedAt = new Date().toISOString();
  }
}

async function createCover(job, inputPath, coverPath) {
  if (job.cover) {
    await fs.copy(job.cover.path, coverPath);
    return;
  }

  await runFfmpeg([
    '-y',
    '-ss', '00:00:01',
    '-i', inputPath,
    '-frames:v', '1',
    coverPath,
  ]);
}

async function createHls(job, inputPath, playlistPath, segmentTemplate) {
  await runFfmpeg([
    '-y',
    '-i', inputPath,
    '-vf', 'scale=-2:1080',
    '-c:v', 'libx264',
    '-preset', 'veryfast',
    '-profile:v', 'high',
    '-crf', '22',
    '-g', '120',
    '-keyint_min', '120',
    '-sc_threshold', '0',
    '-c:a', 'aac',
    '-b:a', '160k',
    '-ac', '2',
    '-hls_time', '6',
    '-hls_playlist_type', 'vod',
    '-hls_segment_filename', segmentTemplate,
    playlistPath,
  ]);
}

function runFfmpeg(args) {
  return new Promise((resolve, reject) => {
    const ffmpegPath = process.env.FFMPEG_PATH || 'ffmpeg';
    const child = spawn(ffmpegPath, args);

    let stderr = '';
    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`ffmpeg exited with code ${code}: ${stderr}`));
      }
    });
  });
}

function parseList(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value;
  return value
    .split(/[\n,]/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function toBoolean(value, fallback = false) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === 'boolean') return value;
  const normalized = String(value).toLowerCase();
  return normalized === 'true' || normalized === '1' || normalized === 'yes';
}

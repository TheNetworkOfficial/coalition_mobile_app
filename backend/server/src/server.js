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

const RENDITION_PROFILES = [
  {
    id: '1080p',
    label: '1080p',
    maxWidth: 1920,
    maxHeight: 1920,
    videoBitrate: 5_000_000,
    audioBitrate: 160_000,
    h264Profile: 'high',
  },
  {
    id: '720p',
    label: '720p',
    maxWidth: 1280,
    maxHeight: 1280,
    videoBitrate: 2_800_000,
    audioBitrate: 128_000,
    h264Profile: 'high',
  },
  {
    id: '480p',
    label: '480p',
    maxWidth: 854,
    maxHeight: 854,
    videoBitrate: 1_400_000,
    audioBitrate: 96_000,
    h264Profile: 'main',
  },
];

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
  const coverPath = path.join(jobMediaDir, 'cover.jpg');
  const mp4Dir = path.join(jobMediaDir, 'mp4');
  const hlsDir = path.join(jobMediaDir, 'hls');

  await fs.ensureDir(mp4Dir);
  await fs.ensureDir(hlsDir);

  try {
    await createCover(job, inputPath, coverPath);
    const mp4Renditions = await transcodeMp4Renditions(inputPath, mp4Dir);
    await packageHlsVariants(mp4Renditions, hlsDir);

    job.outputs = {
      coverUrl: `/media/${job.id}/cover.jpg`,
      playlistUrl: `/media/${job.id}/hls/master.m3u8`,
      renditions: mp4Renditions.map((rendition) => ({
        id: rendition.profile.id,
        label: rendition.profile.label,
        bitrateKbps: Math.round(rendition.profile.videoBitrate / 1000),
        width: rendition.width,
        height: rendition.height,
        mp4Url: `/media/${job.id}/mp4/${rendition.outputName}`,
        playlistUrl: `/media/${job.id}/hls/${rendition.profile.id}/playlist.m3u8`,
      })),
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

async function transcodeMp4Renditions(inputPath, outputDir) {
  const outputs = [];
  for (const profile of RENDITION_PROFILES) {
    const outputName = `${profile.id}.mp4`;
    const outputPath = path.join(outputDir, outputName);
    const scaleFilter = buildScaleFilter(profile);

    await runFfmpeg([
      '-y',
      '-i', inputPath,
      '-vf', scaleFilter,
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-profile:v', profile.h264Profile,
      '-b:v', `${profile.videoBitrate}`,
      '-maxrate', `${Math.round(profile.videoBitrate * 1.07)}`,
      '-bufsize', `${Math.round(profile.videoBitrate * 1.5)}`,
      '-pix_fmt', 'yuv420p',
      '-c:a', 'aac',
      '-b:a', `${profile.audioBitrate}`,
      '-ac', '2',
      outputPath,
    ]);

    const dimensions = await probeVideoDimensions(outputPath);

    outputs.push({
      profile,
      outputPath,
      outputName,
      width: dimensions.width,
      height: dimensions.height,
    });
  }

  return outputs;
}

async function packageHlsVariants(renditions, hlsRoot) {
  const manifestEntries = [];

  for (const rendition of renditions) {
    const variantDir = path.join(hlsRoot, rendition.profile.id);
    await fs.ensureDir(variantDir);

    const segmentTemplate = path.join(variantDir, 'segment_%03d.ts');
    const playlistPath = path.join(variantDir, 'playlist.m3u8');

    await runFfmpeg([
      '-y',
      '-i', rendition.outputPath,
      '-c', 'copy',
      '-hls_time', '6',
      '-hls_playlist_type', 'vod',
      '-hls_flags', 'independent_segments',
      '-hls_segment_filename', segmentTemplate,
      playlistPath,
    ]);

    manifestEntries.push({
      profile: rendition.profile,
      width: rendition.width,
      height: rendition.height,
    });
  }

  const masterPath = path.join(hlsRoot, 'master.m3u8');
  await writeMasterManifest(masterPath, manifestEntries);
}

async function writeMasterManifest(masterPath, entries) {
  const lines = ['#EXTM3U', '#EXT-X-VERSION:3', '#EXT-X-INDEPENDENT-SEGMENTS'];

  for (const entry of entries) {
    const profile = entry.profile;
    const bandwidth = profile.videoBitrate + profile.audioBitrate;
    const averageBandwidth = Math.round(bandwidth * 0.95);
    const width = entry.width || profile.maxWidth;
    const height = entry.height || profile.maxHeight;
    lines.push(
      `#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},AVERAGE-BANDWIDTH=${averageBandwidth},RESOLUTION=${width}x${height},CODECS="avc1.640029,mp4a.40.2"`,
    );
    lines.push(`${profile.id}/playlist.m3u8`);
  }

  await fs.writeFile(masterPath, `${lines.join('\n')}\n`, 'utf8');
}

function buildScaleFilter(profile) {
  const { maxWidth, maxHeight } = profile;
  return [
    `scale=w='if(gt(iw,ih),min(${maxWidth},iw),-2)':h='if(gt(iw,ih),-2,min(${maxHeight},ih))'`,
    'setsar=1',
    'pad=ceil(iw/2)*2:ceil(ih/2)*2',
  ].join(',');
}

async function probeVideoDimensions(filePath) {
  try {
    const output = await runFfprobe([
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height',
      '-of',
      'json',
      filePath,
    ]);
    const parsed = JSON.parse(output);
    const stream = Array.isArray(parsed.streams) ? parsed.streams[0] : null;
    return {
      width: stream && Number.isFinite(stream.width) ? stream.width : null,
      height: stream && Number.isFinite(stream.height) ? stream.height : null,
    };
  } catch (error) {
    console.warn('ffprobe failed to read dimensions for', filePath, error);
    return { width: null, height: null };
  }
}

function runFfprobe(args) {
  return new Promise((resolve, reject) => {
    const ffprobePath = process.env.FFPROBE_PATH || 'ffprobe';
    const child = spawn(ffprobePath, args);

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(`ffprobe exited with code ${code}: ${stderr}`));
      }
    });
  });
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

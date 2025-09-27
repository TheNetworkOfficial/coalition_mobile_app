const posts = new Map();

function ensureKey(post) {
  if (!post || typeof post !== 'object') {
    throw new TypeError('Post must be an object.');
  }
  const key =
    post.id ??
    post.postId ??
    post.slug ??
    post.uuid ??
    post.muxUploadId ??
    post.mux_upload_id ??
    post?.mux?.uploadId ??
    post?.mux?.upload_id;
  if (!key) {
    throw new Error('Post must include an id or mux upload id.');
  }
  return String(key);
}

export function resetPosts() {
  posts.clear();
}

export function seedPosts(initialPosts = []) {
  resetPosts();
  for (const post of initialPosts) {
    upsertPost(post);
  }
}

export function upsertPost(post) {
  const key = ensureKey(post);
  const existing = posts.get(key);
  if (existing && existing !== post) {
    Object.assign(existing, post);
    if (post.mux) {
      existing.mux = { ...(existing.mux ?? {}), ...post.mux };
    }
    return existing;
  }
  posts.set(key, post);
  return post;
}

export function listPosts() {
  return Array.from(posts.values());
}

function findPost({ passthrough, uploadId, assetId }) {
  for (const post of posts.values()) {
    const mux = post.mux ?? {};
    const postPassthrough = mux.passthrough ?? post.mux_passthrough ?? post.passthrough;
    const postUploadId =
      mux.uploadId ?? mux.upload_id ?? post.muxUploadId ?? post.mux_upload_id ?? post.uploadId;
    const postAssetId = mux.assetId ?? mux.asset_id ?? post.muxAssetId ?? post.mux_asset_id;

    if (passthrough && postPassthrough === passthrough) {
      return post;
    }
    if (uploadId && postUploadId === uploadId) {
      return post;
    }
    if (assetId && postAssetId === assetId) {
      return post;
    }
  }
  return null;
}

function isoNow() {
  return new Date().toISOString();
}

export function markAssetCreated({ passthrough, assetId, uploadId }) {
  const post = findPost({ passthrough, uploadId });
  if (!post) {
    return null;
  }
  const mux = { ...(post.mux ?? {}) };
  if (passthrough) mux.passthrough = passthrough;
  if (uploadId) mux.uploadId = uploadId;
  if (assetId) mux.assetId = assetId;
  mux.assetStatus = 'created';
  post.mux = mux;
  post.updatedAt = isoNow();
  return post;
}

export function finalizePost({
  passthrough,
  playbackId,
  playbackUrl,
  duration,
  aspectRatio,
  assetId,
  uploadId,
}) {
  const post = findPost({ passthrough, uploadId, assetId });
  if (!post) {
    return null;
  }
  const mux = { ...(post.mux ?? {}) };
  if (passthrough) mux.passthrough = passthrough;
  if (uploadId) mux.uploadId = uploadId;
  if (assetId) mux.assetId = assetId;

  let resolvedPlaybackUrl = playbackUrl ?? mux.playbackUrl;
  if (!resolvedPlaybackUrl && playbackId) {
    resolvedPlaybackUrl = `https://stream.mux.com/${playbackId}.m3u8`;
  }

  if (playbackId) mux.playbackId = playbackId;
  if (resolvedPlaybackUrl) mux.playbackUrl = resolvedPlaybackUrl;
  if (typeof duration === 'number' && !Number.isNaN(duration)) mux.duration = duration;
  if (aspectRatio) mux.aspectRatio = aspectRatio;

  post.mux = mux;
  post.status = 'ready';
  post.readyAt = isoNow();
  post.updatedAt = post.readyAt;
  return post;
}

export function getPostById(id) {
  return posts.get(String(id));
}

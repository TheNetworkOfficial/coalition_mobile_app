import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3 = new S3Client({ region: process.env.AWS_REGION });
const BUCKET = process.env.BUCKET;
const PREFIX = process.env.PREFIX || "videos";

export const handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");
    const { jobId, files } = body; // files: [{path, contentType}, ...]

    if (!jobId || !Array.isArray(files) || !files.length) {
      return { statusCode: 400, body: JSON.stringify({ ok:false, error:"jobId and files[] required" }) };
    }

    const results = await Promise.all(files.map(async f => {
      const key = `${PREFIX}/${jobId}/${f.path}`;
      const cmd = new PutObjectCommand({ Bucket: BUCKET, Key: key, ContentType: f.contentType || "application/octet-stream" });
      const url = await getSignedUrl(s3, cmd, { expiresIn: 900 }); // 15 min
      return { path: f.path, key, putUrl: url };
    }));

    const publicBaseUrl = process.env.PUBLIC_BASE_URL;
    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "*" },
      body: JSON.stringify({ ok:true, bucket: BUCKET, prefix: PREFIX, jobId, publicBaseUrl, results })
    };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ ok:false, error: String(e) }) };
  }
};

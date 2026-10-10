import { S3Client, CreateBucketCommand, HeadBucketCommand } from '@aws-sdk/client-s3';

const bucket = process.env.S3_BUCKET;
if (!bucket || !process.env.S3_ENDPOINT) throw new Error('Explicit local S3_BUCKET and S3_ENDPOINT are required.');
const client = new S3Client({ region: process.env.S3_REGION || 'us-east-1', endpoint: process.env.S3_ENDPOINT, forcePathStyle: true });
try {
  await client.send(new HeadBucketCommand({ Bucket: bucket }));
} catch (error) {
  if (error.$metadata?.httpStatusCode !== 404 && error.name !== 'NotFound' && error.name !== 'NoSuchBucket') throw error;
  await client.send(new CreateBucketCommand({ Bucket: bucket }));
}
// Private buckets are the default; this does not issue any public ACL or anonymous policy.
console.log('Local private audio bucket is ready.');
client.destroy();

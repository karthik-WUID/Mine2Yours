import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';

const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { encoding: 'utf8' }).split('\0').filter(Boolean);
const signatures = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bsk_(?:live|proj)_[A-Za-z0-9_-]{20,}\b/,
  /\bAIza[0-9A-Za-z_-]{30,}\b/,
  /\bxox[baprs]-[0-9A-Za-z-]{20,}\b/,
];
let issues = 0;
for (const path of files) {
  if (/(?:^|\/)(?:\.env|key\.properties|.*\.(?:jks|keystore|p12|mobileprovision))$/.test(path)) {
    console.error(`Forbidden tracked credential file: ${path}`);
    issues++;
    continue;
  }
  const bytes = await readFile(path);
  if (bytes.length > 2_000_000 || bytes.includes(0)) continue;
  const source = bytes.toString('utf8');
  if (signatures.some(pattern => pattern.test(source))) {
    // Never print the matching value.
    console.error(`Possible credential signature in ${path}; review and remove it.`);
    issues++;
  }
}
if (issues) process.exitCode = 1;
else console.log(`Credential signature check passed for ${files.length} repository source files. This check is not a comprehensive secret scanner.`);

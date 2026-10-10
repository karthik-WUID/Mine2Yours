import { spawn } from "node:child_process";
import { once } from "node:events";
let server,
  closed = false,
  restarts = Promise.resolve();
const compiler = spawn(
  process.execPath,
  ["node_modules/typescript/bin/tsc", "--watch", "--preserveWatchOutput"],
  { stdio: ["ignore", "pipe", "inherit"] },
);
compiler.stdout.on("data", (bytes) => {
  process.stdout.write(bytes);
  if (bytes.toString().includes("Found 0 errors."))
    restarts = restarts.then(async () => {
      if (server && server.exitCode === null) {
        server.kill("SIGTERM");
        await once(server, "exit");
      }
      if (!closed)
        server = spawn(process.execPath, ["dist/main.js"], {
          stdio: "inherit",
        });
    });
});
compiler.on("exit", (code) => {
  if (!closed) {
    server?.kill("SIGTERM");
    process.exitCode = code || 1;
  }
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    closed = true;
    compiler.kill(signal);
    server?.kill(signal);
  });

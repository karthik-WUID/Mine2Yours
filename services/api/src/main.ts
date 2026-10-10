import "reflect-metadata";
import "dotenv/config";
import { NestFactory } from "@nestjs/core";
import { ValidationPipe } from "@nestjs/common";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import { json } from "express";
import helmet from "helmet";
import { randomUUID } from "node:crypto";
import { AppModule } from "./app.module";
import { RealtimeService } from "./realtime/realtime.service";
import { PrivacyService } from "./privacy/privacy.service";
import { enrichOpenApi } from "./common/openapi";
import { SafeExceptionFilter } from "./common/errors";
import { pricing } from "./analytics/usage.service";
import { globalBudgetCaps } from "./common/limits";
export async function bootstrap() {
  if (process.env.NODE_ENV === "production") {
    if (process.env.ENABLE_DEV_AUTH === "true")
      throw new Error("ENABLE_DEV_AUTH must be disabled in production");
    if (
      !process.env.DATA_ENCRYPTION_KEY ||
      !process.env.AUDIO_SIGNING_KEY ||
      process.env.AUDIO_SIGNING_KEY.length < 32
    )
      throw new Error("Production encryption and signing keys are required");
    if (
      !process.env.GLOBAL_DAILY_AI_BUDGET_USD ||
      !process.env.GLOBAL_MONTHLY_AI_BUDGET_USD
    )
      throw new Error(
        "Production requires explicit service-wide spending limits",
      );
    if (!process.env.AI_PRICING_VERSION)
      throw new Error(
        "Production requires a reviewed, versioned provider pricing configuration",
      );
  }
  globalBudgetCaps();
  for (const value of Object.values(pricing()).filter(
    (v) => typeof v === "number",
  ))
    if (!Number.isFinite(value) || Number(value) <= 0)
      throw new Error("Provider unit prices must be finite and positive");
  const app = await NestFactory.create(AppModule, {
    bodyParser: false,
    logger: ["error", "warn"],
  });
  app.setGlobalPrefix("v1");
  app.enableShutdownHooks();
  app.use(helmet());
  if (process.env.TRUST_PROXY)
    app
      .getHttpAdapter()
      .getInstance()
      .set("trust proxy", Number(process.env.TRUST_PROXY));
  app.use(
    json({
      limit: "6mb",
      verify: (req: any, res, body) => {
        if (req.url.startsWith("/v1/billing/webhook"))
          req.rawBody = Buffer.from(body);
      },
    }),
  );
  const origins = (
    process.env.CORS_ORIGINS ||
    "http://localhost:5173,http://localhost:3001,http://127.0.0.1:5173"
  ).split(",");
  app.enableCors({
    origin: (
      origin: string | undefined,
      callback: (error: Error | null, allowed?: boolean) => void,
    ) => {
      const allowed =
        !origin ||
        origins.includes(origin) ||
        (process.env.NODE_ENV !== "production" &&
          /^http:\/\/(localhost|127\.0\.0\.1)(:[0-9]+)?$/.test(origin));
      callback(null, allowed);
    },
    credentials: false,
  });
  const rates = new Map<string, { count: number; ends: number }>();
  app.use((req: any, res: any, next: any) => {
    const requestId = randomUUID(),
      start = Date.now();
    res.setHeader("X-Request-ID", requestId);
    if (/\/groups\/[^/]+\/workers(?:\/|$)/.test(req.path)) {
      res.setHeader("Cache-Control", "no-store");
      res.setHeader("Pragma", "no-cache");
    }
    const route = req.path.includes("/auth/")
      ? "auth"
      : req.path.includes("/messages") && req.method === "POST" && !req.path.endsWith("/ack")
        ? "message"
        : "api";
    const key = `${req.ip}:${route}`;
    const time = Date.now(),
      period = route === "auth" ? 300000 : 60000,
      // Coarse IP protection complements per-user budgets in AuthGuard.
      limit = route === "auth" ? 20 : route === "message" ? 600 : 2000;
    const prior = rates.get(key);
    const entry =
      prior && prior.ends > time ? prior : { count: 0, ends: time + period };
    entry.count++;
    rates.set(key, entry);
    if (rates.size > 10000)
      for (const [id, v] of rates) if (v.ends < time) rates.delete(id);
    res.once("finish", () =>
      process.stdout.write(
        JSON.stringify({
          time: new Date().toISOString(),
          requestId,
          method: req.method,
          route: req.route?.path || "unmatched",
          status: res.statusCode,
          latencyMs: Date.now() - start,
        }) + "\n",
      ),
    );
    if (entry.count > limit) {
      res.setHeader("Retry-After", Math.ceil((entry.ends - time) / 1000));
      return res
        .status(429)
        .json({
          code: "RATE_LIMITED",
          message: "Too many requests. Try again shortly.",
        });
    }
    if (
      process.env.NODE_ENV === "production" &&
      !req.secure &&
      req.path !== "/v1/health"
    )
      return res
        .status(403)
        .json({ code: "TLS_REQUIRED", message: "HTTPS is required." });
    next();
  });
  app.useGlobalFilters(new SafeExceptionFilter());
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      validationError: { target: false, value: false },
    }),
  );
  const document = enrichOpenApi(
    SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle("Mine2YourLingo API")
        .setDescription(
          "Private multilingual communication API. Development authentication requires explicit opt-in.",
        )
        .setVersion("1.0")
        .addBearerAuth()
        .build(),
    ),
  );
  SwaggerModule.setup("v1/docs", app, document, {
    jsonDocumentUrl: "v1/openapi.json",
  });
  app.get(RealtimeService).attach(app.getHttpServer());
  await app.init();
  const privacy = app.get(PrivacyService);
  await privacy.retain();
  await app.listen(
    Number(process.env.PORT || 3000),
    process.env.HOST || "127.0.0.1",
  );
  const retention = setInterval(
    () =>
      void privacy
        .retain()
        .catch(() => process.stderr.write('{"event":"retention.failed"}\n')),
    3600000,
  );
  retention.unref();
  process.stdout.write(
    JSON.stringify({
      event: "api.started",
      port: app.getHttpServer().address().port,
      environment: process.env.NODE_ENV || "development",
    }) + "\n",
  );
  return app;
}
if (require.main === module)
  void bootstrap().catch(() => {
    process.stderr.write(
      '{"event":"api.startup_failed","message":"Check required environment and dependency connectivity."}\n',
    );
    process.exitCode = 1;
  });

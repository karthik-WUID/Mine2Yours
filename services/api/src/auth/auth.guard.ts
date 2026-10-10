import { CanActivate, ExecutionContext, Injectable, HttpException } from "@nestjs/common";
import { AuthService } from "./auth.service";
@Injectable()
export class AuthGuard implements CanActivate {
  private readonly rates = new Map<string, { count: number; ends: number }>();
  constructor(private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    const header = req.headers.authorization;
    const token =
      typeof header === "string" && header.startsWith("Bearer ")
        ? header.slice(7)
        : undefined;
    const identity = await this.auth.authenticate(token);
    // All authenticated phones retain their own budgets, even behind one proxy/NAT.
    const receipt = req.method === "POST" && /^\/v1\/messages\/[^/]+\/ack$/.test(req.path);
    const route = receipt ? "receipt" : req.method === "POST" && req.path.startsWith("/v1/messages") ? "message" : "api";
    const key = `${identity.user.id}:${route}`;
    const time = Date.now();
    const previous = this.rates.get(key);
    const entry = previous && previous.ends > time ? previous : { count: 0, ends: time + 60000 };
    this.rates.set(key, entry);
    const limit = route === "message" ? 30 : route === "receipt" ? 360 : 180;
    if (++entry.count > limit) {
      req.res.setHeader("Retry-After", Math.ceil((entry.ends - time) / 1000));
      throw new HttpException({ code: "RATE_LIMITED", message: "Please wait a moment before trying again." }, 429);
    }
    if (this.rates.size > 10000) for (const [id, value] of this.rates) if (value.ends < time) this.rates.delete(id);
    req.user = identity.user;
    req.sessionId = identity.sessionId;
    return true;
  }
}

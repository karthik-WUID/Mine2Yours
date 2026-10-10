import { Injectable, OnModuleDestroy } from "@nestjs/common";
import Redis from "ioredis";
import { randomUUID } from "node:crypto";
import { WebSocket, WebSocketServer } from "ws";
import { AuthService } from "../auth/auth.service";
import { Store } from "../common/store";
import { State } from "../common/types";
import { memberState } from "../common/profile";
@Injectable()
export class RealtimeService implements OnModuleDestroy {
  private readonly instanceId = randomUUID();
  private publisher?: Redis;
  private subscriber?: Redis;
  private server?: WebSocketServer;
  private clients = new Map<WebSocket, { userId: string; token: string }>();
  constructor(
    private readonly auth: AuthService,
    private readonly store: Store,
  ) {}
  attach(server: any) {
    if (process.env.REDIS_URL) {
      this.publisher = new Redis(process.env.REDIS_URL);
      this.subscriber = new Redis(process.env.REDIS_URL);
      this.publisher.on("error", () => {});
      this.subscriber.on("error", () => {});
      void this.subscriber.subscribe("mine2yourlingo:events");
      this.subscriber.on("message", (_, payload) => {
        try {
          const event = JSON.parse(payload);
          if (
            event.origin !== this.instanceId &&
            Array.isArray(event.users) &&
            event.users.length <= 10000 &&
            typeof event.type === "string" &&
            (typeof event.data?.messageId === "string" ||
              (["group.updated", "member.language.updated"].includes(event.type) &&
                typeof event.data?.groupId === "string"))
          )
            void this.emit(
              event.users,
              event.type,
              event.data,
              (state, userId) =>
                ["group.updated", "member.language.updated"].includes(event.type)
                  ? state.members.some(
                      (v) =>
                        v.groupId === event.data.groupId && v.userId === userId,
                    ) && (event.type !== "member.language.updated" || state.members.some(v => v.groupId === event.data.groupId && v.userId === event.data.member?.userId)) || (event.type === "group.updated" && event.data.removedUserIds?.includes(userId))
                  : this.authorized(state, userId, event.data.messageId),
            ).catch(() => {});
        } catch {}
      });
    }
    const allowedOrigins = (
      process.env.CORS_ORIGINS || "http://localhost:5173,http://localhost:3001"
    ).split(",");
    this.server = new WebSocketServer({
      server,
      path: "/v1/realtime",
      maxPayload: 4096,
      perMessageDeflate: false,
      verifyClient: ({ origin, req }: { origin: string; req: any }) => {
        if (
          process.env.NODE_ENV === "production" &&
          !(req.socket as any).encrypted &&
          !(
            process.env.TRUST_PROXY &&
            req.headers["x-forwarded-proto"] === "https"
          )
        )
          return false;
        return (
          !origin ||
          allowedOrigins.includes(origin) ||
          (process.env.NODE_ENV !== "production" &&
            /^http:\/\/(localhost|127\.0\.0\.1)(:[0-9]+)?$/.test(origin))
        );
      },
    });
    this.server.on("connection", (socket, req) => {
      if (this.server!.clients.size > 1000) {
        socket.close(1013, "Connection limit");
        return;
      }
      const expire = setTimeout(
        () => socket.close(4001, "Access token refresh required"),
        14 * 60000,
      );
      const initial = setTimeout(() => {
        if (!this.clients.has(socket))
          socket.close(4001, "Authentication required");
      }, 5000);
      socket.on("close", () => {
        clearTimeout(expire);
        clearTimeout(initial);
        this.clients.delete(socket);
      });
      socket.on("error", () => {});
      const authenticate = async (token: string) => {
        try {
          const identity = await this.auth.authenticate(token);
          if (
            [...this.clients.values()].filter(
              (v) => v.userId === identity.user.id,
            ).length >= 5
          ) {
            socket.close(1013, "Device connection limit");
            return;
          }
          this.clients.set(socket, { userId: identity.user.id, token });
          clearTimeout(initial);
          socket.send(
            JSON.stringify({
              type: "authenticated",
              data: { userId: identity.user.id },
            }),
          );
          // Register first, then snapshot. Concurrent updates carry a version.
          const groups = await this.store.read(s => [...new Set(s.members.filter(m => m.userId === identity.user.id).map(m => m.groupId))]
            .map(groupId => ({ groupId, members: s.members.filter(m => m.groupId === groupId)
              .flatMap(m => { const user = s.users.find(u => u.id === m.userId); return user ? [memberState(user)] : []; }) })));
          for (const group of groups) {
            if (await this.store.read(s => s.members.some(m => m.groupId === group.groupId && m.userId === identity.user.id)) && socket.readyState === WebSocket.OPEN)
              socket.send(JSON.stringify({ type: "team.members.snapshot", data: group }));
          }
        } catch {
          socket.close(4001, "Authentication failed");
        }
      };
      const header = req.headers.authorization;
      if (header?.startsWith("Bearer ")) void authenticate(header.slice(7));
      socket.on("message", async (bytes) => {
        try {
          const message = JSON.parse(bytes.toString());
          if (!this.clients.has(socket)) {
            if (
              message.type !== "authenticate" ||
              typeof message.accessToken !== "string"
            )
              return socket.close(4001, "Authentication required");
            await authenticate(message.accessToken);
            return;
          }
          if (message.type === "ping")
            socket.send(JSON.stringify({ type: "pong", data: {} }));
        } catch {
          socket.close(4000, "Invalid event");
        }
      });
    });
  }
  async emit(
    userIds: string[],
    type: string,
    data: unknown,
    authorize?: (s: State, userId: string) => boolean,
  ) {
    await Promise.all(
      [...this.clients]
        .filter(([, identity]) => userIds.includes(identity.userId))
        .map(async ([socket, identity]) => {
          try {
            await this.auth.authenticate(identity.token);
            if (
              authorize &&
              !(await this.store.read((s) => authorize(s, identity.userId)))
            )
              return;
            if (
              socket.readyState === WebSocket.OPEN &&
              socket.bufferedAmount < 65536
            )
              socket.send(JSON.stringify({ type, data }));
          } catch {
            socket.close(4001, "Session revoked");
          }
        }),
    );
  }
  private authorized(state: State, userId: string, messageId: string) {
    const message = state.messages.find((v) => v.id === messageId);
    return (
      !!message &&
      message.expiresAt > new Date().toISOString() &&
      state.members.some(
        (v) => v.groupId === message.groupId && v.userId === userId,
      ) &&
      (message.senderId === userId ||
        (message.state !== "REVIEW_REQUIRED" &&
          state.recipients.some(
            (v) => v.messageId === messageId && v.userId === userId,
          )))
    );
  }
  async message(messageId: string, type = "message.updated") {
    const targets = await this.store.read((s) => {
      const m = s.messages.find((v) => v.id === messageId);
      return m
        ? {
            groupId: m.groupId,
            state: m.state,
            users: [
              m.senderId,
              ...s.recipients
                .filter((v) => v.messageId === messageId)
                .map((v) => v.userId),
            ],
          }
        : undefined;
    });
    if (targets) {
      const event = {
        origin: this.instanceId,
        users: targets.users,
        type:
          type === "message.ready" && targets.state !== "READY"
            ? "message.updated"
            : type,
        data: { messageId, groupId: targets.groupId, state: targets.state },
      };
      await this.emit(event.users, event.type, event.data, (state, u) =>
        this.authorized(state, u, messageId),
      );
      if (this.publisher)
        await this.publisher.publish(
          "mine2yourlingo:events",
          JSON.stringify(event),
        );
    }
  }
  // Receipts update status only, never announce the message as new again.
  async receipt(messageId: string, userId: string, state: string) {
    const sender = await this.store.read((s) => s.messages.find((m) => m.id === messageId)?.senderId);
    if (!sender) return;
    const event = {
      origin: this.instanceId,
      users: [...new Set([sender, userId])],
      type: "message.receipt",
      data: { messageId, userId, state },
    };
    await this.emit(event.users, event.type, event.data, (s, u) => this.authorized(s, u, messageId));
    if (this.publisher) await this.publisher.publish("mine2yourlingo:events", JSON.stringify(event));
  }
  async member(userId: string) {
    const groups = await this.store.read(s => [...new Set(s.members.filter(m => m.userId === userId).map(m => m.groupId))]);
    for (const groupId of groups) {
      const snapshot = await this.store.read(s => {
        const user = s.users.find(u => u.id === userId);
        return user ? { member: memberState(user), users: s.members.filter(m => m.groupId === groupId).map(m => m.userId) } : undefined;
      });
      if (!snapshot) continue;
      const event = { origin: this.instanceId, users: snapshot.users, type: "member.language.updated", data: { groupId, member: snapshot.member } };
      await this.emit(event.users, event.type, event.data, (s, viewerId) => s.members.some(m => m.groupId === groupId && m.userId === viewerId) && s.members.some(m => m.groupId === groupId && m.userId === userId));
      if (this.publisher) await this.publisher.publish("mine2yourlingo:events", JSON.stringify(event));
    }
  }
  async group(groupId: string, removedUserIds: string[] = []) {
    const users = await this.store.read((state) => [
      ...new Set([
        ...state.members
          .filter((v) => v.groupId === groupId)
          .map((v) => v.userId),
        ...removedUserIds,
      ]),
    ]);
    const event = {
      origin: this.instanceId,
      users,
      type: "group.updated",
      data: { groupId, removedUserIds },
    };
    await this.emit(
      users,
      event.type,
      event.data,
      (state, userId) =>
        state.members.some(
          (v) => v.groupId === groupId && v.userId === userId,
        ) || removedUserIds.includes(userId),
    );
    if (this.publisher)
      await this.publisher.publish(
        "mine2yourlingo:events",
        JSON.stringify(event),
      );
  }
  async onModuleDestroy() {
    for (const socket of this.clients.keys())
      socket.close(1001, "Server shutdown");
    this.server?.close();
    await this.publisher?.quit();
    await this.subscriber?.quit();
  }
}

import { Module } from "@nestjs/common";
import { Store } from "./common/store";
import { AuthService } from "./auth/auth.service";
import { AuthGuard } from "./auth/auth.guard";
import { AuthController } from "./auth/auth.controller";
import { GroupsService } from "./groups/groups.service";
import { GroupsController } from "./groups/groups.controller";
import { WorkersController } from "./groups/workers.controller";
import { WorkersService } from "./groups/workers.service";
import { PersonnelMediaService } from "./groups/personnel-media.service";
import { UsersController } from "./users/users.controller";
import { MessagingService } from "./messaging/messaging.service";
import { MessagingController } from "./messaging/messaging.controller";
import { RealtimeService } from "./realtime/realtime.service";
import { AudioService } from "./audio/audio.service";
import { AudioController } from "./audio/audio.controller";
import { HttpAiProviders } from "./ai/providers";
import { BillingService } from "./billing/billing.service";
import { BillingController } from "./billing/billing.controller";
import { UsageService } from "./analytics/usage.service";
import { AnalyticsController } from "./analytics/analytics.controller";
import { PrivacyService } from "./privacy/privacy.service";
import { PrivacyController } from "./privacy/privacy.controller";
import { SystemController } from "./common/system.controller";
@Module({
  controllers: [
    AuthController,
    GroupsController,
    WorkersController,
    UsersController,
    MessagingController,
    AudioController,
    BillingController,
    AnalyticsController,
    PrivacyController,
    SystemController,
  ],
  providers: [
    Store,
    AuthService,
    AuthGuard,
    GroupsService,
    WorkersService,
    PersonnelMediaService,
    MessagingService,
    RealtimeService,
    AudioService,
    HttpAiProviders,
    BillingService,
    UsageService,
    PrivacyService,
  ],
})
export class AppModule {}

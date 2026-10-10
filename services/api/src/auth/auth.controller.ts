import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from "@nestjs/common";
import { AuthService } from "./auth.service";
import { AuthGuard } from "./auth.guard";
import {
  DeviceSessionDto,
  DevAuthDto,
  RefreshDto,
  OtpRequestDto,
  OtpVerifyDto,
  PhoneLoginRequestDto,
  PhoneLoginVerifyDto,
} from "../common/validation";
import { ApiTags } from "@nestjs/swagger";
@ApiTags("Authentication")
@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}
  @Post("device") device(@Body() input: DeviceSessionDto) { return this.auth.deviceSession(input); }
  @Post("device/link") @UseGuards(AuthGuard) bindDevice(@Req() req: any, @Body() input: DeviceSessionDto) { return this.auth.bindDevice(req.user.id, input); }
  @Post("dev") dev(@Body() input: DevAuthDto) {
    return this.auth.dev(input);
  }
  @Post("phone/request") requestPhone(@Body() input: PhoneLoginRequestDto) {
    return this.auth.requestPhoneLogin(input.phone);
  }
  @Post("phone/verify") verifyPhone(@Body() input: PhoneLoginVerifyDto) {
    return this.auth.verifyPhoneLogin(input);
  }
  @Post("phone/link") @UseGuards(AuthGuard) linkPhone(@Req() req: any, @Body() input: PhoneLoginVerifyDto) {
    return this.auth.linkPhone(req.user.id, input);
  }
  @Post("refresh") refresh(@Body() input: RefreshDto) {
    return this.auth.refresh(input.refreshToken);
  }
  @Post("logout") @UseGuards(AuthGuard) logout(@Req() req: any) {
    return this.auth.logout(req.sessionId);
  }
  @Get("capabilities") capabilities() {
    return {
      developmentSimulator: this.auth.devEnabled(),
      phoneLogin: this.auth.devEnabled() || this.auth.otpEnabled(),
      phoneOtp: this.auth.otpEnabled(),
      email: false,
    };
  }
  @Post("otp/request") otp(@Body() input: OtpRequestDto) {
    return this.auth.requestOtp(input.phone);
  }
  @Post("otp/verify") verifyOtp(@Body() input: OtpVerifyDto) {
    return this.auth.verifyOtp(input);
  }
}

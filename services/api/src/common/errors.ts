import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
} from "@nestjs/common";
@Catch()
export class SafeExceptionFilter implements ExceptionFilter {
  catch(error: any, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse();
    const status =
      error instanceof HttpException
        ? error.getStatus()
        : typeof error?.status === "number"
          ? error.status
          : 500;
    const body =
      error instanceof HttpException
        ? error.getResponse()
        : {
            code: status === 400 ? "INVALID_BODY" : "INTERNAL_ERROR",
            message:
              status === 400
                ? "Request body is invalid."
                : "The request could not be completed.",
          };
    response
      .status(status)
      .json(
        typeof body === "string" ? { statusCode: status, message: body } : body,
      );
  }
}

import { getMetadataStorage } from "class-validator";
import * as dtos from "./validation";
/** Derive request schemas from the same constraints used by the validation pipe. */
export function enrichOpenApi(document: any) {
  for (const dto of Object.values(dtos)) {
    const properties: Record<string, any> = {},
      optional = new Set<string>();
    const fields = getMetadataStorage().getTargetValidationMetadatas(
      dto as any,
      (dto as any).name,
      false,
      false,
    );
    for (const field of fields) {
      const schema = (properties[field.propertyName] ||= {});
      const name = field.name;
      if (name === "isOptional") optional.add(field.propertyName);
      if (name === "isString" || name === "isUuid" || name === "matches")
        schema.type = "string";
      if (name === "isBoolean") schema.type = "boolean";
      if (name === "isNumber") schema.type = "number";
      if (name === "isInt") schema.type = "integer";
      if (name === "isUuid") schema.format = "uuid";
      if (name === "minLength") schema.minLength = field.constraints[0];
      if (name === "maxLength") schema.maxLength = field.constraints[0];
      if (name === "min") schema.minimum = field.constraints[0];
      if (name === "max") schema.maximum = field.constraints[0];
      if (name === "isIn") {
        schema.enum = field.constraints[0];
        schema.type = typeof field.constraints[0][0];
      }
      if (name === "matches") schema.pattern = field.constraints[0].source;
    }
    document.components.schemas[(dto as any).name] = {
      type: "object",
      additionalProperties: false,
      properties,
      required: Object.keys(properties).filter((name) => !optional.has(name)),
    };
  }
  document.components.schemas.Profile = {
    type: "object",
    required: [
      "id",
      "displayName",
      "spokenLanguage",
      "listeningLanguage",
      "providerConsent",
    ],
    properties: {
      id: { type: "string", format: "uuid" },
      displayName: { type: "string" },
      spokenLanguage: { type: "string" },
      listeningLanguage: { type: "string" },
      receivingMode: {
        type: "string",
        enum: ["notification", "automatic", "headphones", "silent"],
      },
      providerConsent: { type: "boolean" },
      isAdmin: { type: "boolean" },
      createdAt: { type: "string", format: "date-time" },
    },
  };
  document.components.schemas.SessionResponse = {
    type: "object",
    required: ["accessToken", "refreshToken", "expiresIn", "user"],
    properties: {
      accessToken: { type: "string" },
      refreshToken: { type: "string" },
      expiresIn: { type: "integer", example: 900 },
      user: { $ref: "#/components/schemas/Profile" },
      mode: {
        type: "string",
        enum: ["development-simulator", "development-phone", "verified-phone"],
      },
    },
  };
  const bodyMap: Record<string, string> = {
    "/v1/auth/phone/request": "PhoneLoginRequestDto",
    "/v1/auth/phone/link": "PhoneLoginVerifyDto",
    "/v1/auth/phone/verify": "PhoneLoginVerifyDto",
    "/v1/groups/{team}/workers": "WorkerDto",
    "/v1/groups/{team}/workers/{id}/document": "WorkerDocumentDto",
    "/v1/groups/{team}/workers/{id}/payments": "WorkerPaymentDto",
    "/v1/groups/{team}/workers/{id}/work": "WorkerLogDto",
    "/v1/auth/dev": "DevAuthDto",
    "/v1/auth/refresh": "RefreshDto",
    "/v1/auth/otp/request": "OtpRequestDto",
    "/v1/auth/otp/verify": "OtpVerifyDto",
    "/v1/groups": "GroupDto",
    "/v1/groups/join": "JoinDto",
    "/v1/groups/{id}/invitations": "InvitationDto",
    "/v1/messages": "MessageDto",
    "/v1/messages/{id}/ack": "AckDto",
    "/v1/audio/transcribe": "TranscribeDto",
    "/v1/billing/purchases/verify": "PurchaseDto",
    "/v1/users/me/devices": "DeviceDto",
  };
  for (const [path, dto] of Object.entries(bodyMap))
    if (document.paths[path]?.post)
      document.paths[path].post.requestBody = {
        required: true,
        content: {
          "application/json": {
            schema: { $ref: `#/components/schemas/${dto}` },
          },
        },
      };
  for (const [path, dto] of Object.entries({
    "/v1/users/me": "ProfileDto",
    "/v1/groups/{team}/workers/{id}": "WorkerDto",
    "/v1/groups/{id}": "UpdateGroupDto",
    "/v1/groups/{id}/members/{userId}": "MemberRoleDto",
  }))
    if (document.paths[path]?.patch)
      document.paths[path].patch.requestBody = {
        required: true,
        content: {
          "application/json": {
            schema: { $ref: `#/components/schemas/${dto}` },
          },
        },
      };
  document.paths["/v1/users/me"].delete.requestBody = {
    required: true,
    content: {
      "application/json": {
        schema: { $ref: "#/components/schemas/DeleteAccountDto" },
      },
    },
  };
  for (const path of [
    "/v1/auth/dev",
    "/v1/auth/refresh",
    "/v1/auth/otp/verify",
    "/v1/auth/phone/verify",
  ])
    document.paths[path].post.responses["201"] = {
      description: "Authenticated session. Credentials are never logged.",
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/SessionResponse" },
        },
      },
    };
  document.info.description +=
    " Audio requires verified PCM WAV. Missing providers or reviewed pricing fail closed. Message review, delivery and playback are separate states. See packages/api-contracts for complete public response interfaces.";
  return document;
}

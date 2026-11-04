import { defineRailway, github, project, service, volume } from "railway/iac";
// This repository manages only its own resources in the environment. Other
// repositories export their own partial name.
// See https://docs.railway.com/infrastructure-as-code#multi-repo-projects
export const partial = "popularia-autopilot";
export default defineRailway(() => {
  const cezarData = volume("popularia-autopilot-volume", {
    sizeMB: 5000,
    region: "us-east4-eqdc4a",
    allowOnlineResize: true,
    alerts: { usage: { "80": {}, "95": {}, "100": {} } },
  });

  const populariaAutopilot = service("popularia-autopilot", {
    source: github("vinicius-m-santos/popularia-autopilot", { branch: "main", checkSuites: false }),
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    healthcheck: "/healthz",
    healthcheckTimeout: 300,
    deploy: { restartPolicyType: "ON_FAILURE", restartPolicyMaxRetries: 3 },
    replicas: { "us-east4-eqdc4a": 1 },
    volumeMounts: { "/data": cezarData },
  });

  return project("welcoming-serenity", {
    variables: { managed: false },
    resources: [cezarData, populariaAutopilot],
  });
});

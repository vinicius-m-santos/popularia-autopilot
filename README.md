# Popularia Autopilot — Railway bootstrap (experimental)

This is a first-pass Docker image, not a validated production deployment.

## Deploy
1. Push these files to a private GitHub repository.
2. In Railway, create a project and a service from that repository.
3. Add a persistent volume mounted at `/workspace` (Cezar stores configuration under `.ai/cezar/` in the active workspace).
4. Set PORT=4321 and verify Cezar binds to 0.0.0.0. Its CLI/server binding flags must be confirmed for the installed version; do not expose a public domain until authentication is configured.
5. Deploy, inspect logs and test health via private access first.
6. Configure OpenCode's DeepSeek provider, GitHub credentials, and Jira integration only after access controls are in place.

## Caveats
- No public authentication/reverse proxy is bundled.
- `cezar-run` and `opencode-ai` versions are unpinned; pin after smoke testing.
- PHP tooling here is minimal; add Composer and project-specific extensions before backend tasks.
- Multi-repo workspace setup and automatic Jira queue are not configured yet.
- Railway services with volumes cannot use horizontal replicas; concurrent agents in a single service still need resource limits.

# Selected hosting approach

The owner selected Render and will perform deployment. The implementation includes a Dockerfile and root render.yaml. Use [render-deployment.md](render-deployment.md) as the current instructions.

Authentication is individual, revocable leadership codes. Firebase/Google login and Google Cloud Run were planning proposals and are not part of this implementation.

The existing sheet is currently readable by link. Public-sheet mode works with that existing state; private Sheets API/service-account mode is also implemented. No Google billing-enabled project is needed for the existing public-sheet adapter. Restrict Google sharing and configure the private adapter if the sheet should only be visible to authorized service identities.

Render Free has idle sleep/cold-start limitations. The app handles unavailable/stale results and allows retry. It does not send background keepalive requests.

References: [Render Docker deployment](https://render.com/docs/docker), [Render free-service limits](https://render.com/docs/free), [Blueprint specification](https://render.com/docs/blueprint-spec).

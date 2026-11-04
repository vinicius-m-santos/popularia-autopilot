FROM node:22-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates openssh-client python3 make g++ php-cli php-xml php-mbstring php-curl unzip && rm -rf /var/lib/apt/lists/*
RUN npm install -g cezar-run opencode-ai
WORKDIR /workspace
ENV HOME=/workspace
EXPOSE 4321
CMD ["cezar-run"]

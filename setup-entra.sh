#!/usr/bin/env bash
# OwnDesk: create or update the Entra ID app registration for an installation (MVP §3.2 A).
#
# Run in Azure Cloud Shell (Bash) after the Portal wizard:
#   bash <(curl -fsSL https://raw.githubusercontent.com/MouradLagsir19999/owndesk-deploy/main/setup-entra.sh) <resource-group> <installatienaam>
#
# Why a script and not the template: the Graph Bicep extension returned "Insufficient privileges" when the
# deployment came from the Azure Portal or Cloud Shell (22-10-2026), while `az ad` works there.
#
# Safe to run again. No client secret is created: the app signs in with the installation's managed
# identity through a federated credential. Like TOPdesk, the app gets Mail.ReadWrite and Mail.Send as
# application permissions; after admin consent these apply to ALL mailboxes in the tenant. Limiting them to
# the shared mailbox is an optional step in the setup wizard (Exchange RBAC for Applications).
# Needs: Application Administrator (or Global Administrator) in Entra ID, Contributor on the resource group.

set -euo pipefail

RG="${1:?Gebruik: setup-entra.sh <resource-group> <installatienaam>}"
NAAM="${2:?Gebruik: setup-entra.sh <resource-group> <installatienaam>}"

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors >/dev/null

TENANT=$(az account show --query tenantId -o tsv)
WEB="ca-${NAAM}-web"
JOB="caj-${NAAM}-worker"
DISPLAY="OwnDesk (${NAAM})"
GRAPH="00000003-0000-0000-c000-000000000000"

echo "1/5 Installatie opzoeken in ${RG}..."
MI_PRINCIPAL=$(az identity show -g "$RG" -n "id-${NAAM}" --query principalId -o tsv)
FQDN=$(az containerapp show -g "$RG" -n "$WEB" --query properties.configuration.ingress.fqdn -o tsv)
REDIRECT="https://${FQDN}/signin-oidc"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "2/5 App-registratie '${DISPLAY}'..."
APP_ID=$(az ad app list --filter "displayName eq '${DISPLAY}'" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "$DISPLAY" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  echo "   aangemaakt: ${APP_ID}"
  echo '[]' >"$TMP/existing.json"
else
  echo "   bestaat al: ${APP_ID}"
  az ad app show --id "$APP_ID" --query appRoles -o json >"$TMP/existing.json"
fi

# Keep the id of a role that already exists (Entra refuses to swap active roles); new roles get a stable id.
python3 - "$TMP/existing.json" "$TMP/roles.json" <<'PY'
import json, sys, uuid
existing = {r["value"]: r["id"] for r in json.load(open(sys.argv[1]))}
roles = [{"id": existing.get(n, str(uuid.uuid5(uuid.NAMESPACE_URL, "owndesk-role-" + n))), "value": n, "displayName": n,
          "description": "OwnDesk-rol " + n, "allowedMemberTypes": ["User"], "isEnabled": True}
         for n in ("Medewerker", "Behandelaar", "Beheerder")]
json.dump(roles, open(sys.argv[2], "w"))
PY
# User.Read (sign-in); application: User.Read.All, Group.Read.All, Mail.ReadWrite, Mail.Send.
cat >"$TMP/access.json" <<EOF
[{"resourceAppId":"${GRAPH}","resourceAccess":[
  {"id":"e1fe6dd8-ba31-4d61-89e7-88639da4683d","type":"Scope"},
  {"id":"df021288-bdef-4463-88db-98f22de89214","type":"Role"},
  {"id":"5b567255-7703-4780-807c-7be8301ae99b","type":"Role"},
  {"id":"e2a3a72e-5f79-4c64-b1b1-878b674786c9","type":"Role"},
  {"id":"b633e1c5-b582-4048-a93e-9f11b44c7e96","type":"Role"}
]}]
EOF

az ad app update --id "$APP_ID" --web-redirect-uris "$REDIRECT" \
  --app-roles "@$TMP/roles.json" --required-resource-accesses "@$TMP/access.json" --only-show-errors

echo "3/5 Service principal..."
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
[ -n "$SP_ID" ] || SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

echo "4/5 Koppeling met de managed identity (geen wachtwoord)..."
if ! az ad app federated-credential list --id "$APP_ID" --query "[?name=='managed-identity'].name" -o tsv | grep -q managed-identity; then
  az ad app federated-credential create --id "$APP_ID" --only-show-errors -o none --parameters "{
    \"name\": \"managed-identity\",
    \"issuer\": \"https://login.microsoftonline.com/${TENANT}/v2.0\",
    \"subject\": \"${MI_PRINCIPAL}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
fi

echo "5/5 App-instellingen bijwerken..."
VARS=("AzureAd__ClientId=${APP_ID}" "AzureAd__ServicePrincipalObjectId=${SP_ID}")
az containerapp update -g "$RG" -n "$WEB" --set-env-vars "${VARS[@]}" --only-show-errors -o none
az containerapp job update -g "$RG" -n "$JOB" --set-env-vars "${VARS[@]}" --only-show-errors -o none

cat <<EOF

Klaar.
  App:            https://${FQDN}
  Toestemming:    https://login.microsoftonline.com/${TENANT}/adminconsent?client_id=${APP_ID}
  Setupcode:      Key Vault in ${RG}, geheim 'setup-code'

Open de app en volg de setup-wizard.
EOF

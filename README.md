# OwnDesk installeren in Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMouradLagsir19999%2Fowndesk-deploy%2Fmain%2FmainTemplate.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FMouradLagsir19999%2Fowndesk-deploy%2Fmain%2FcreateUiDefinition.json)

1. Klik op **Deploy to Azure** en volg de schermen (abonnement, nieuwe resourcegroep, regio, gedeelde mailbox, budget).
2. Open daarna in de Portal je implementatie → **Uitvoer** → `appUrl`.
3. De setup-wizard in OwnDesk vraagt je in te loggen als **Globale beheerder** en richt inloggen, toestemming en jouw rol Beheerder zelf in.

Deze repository bevat alleen de installatiebestanden (`mainTemplate.json`, `createUiDefinition.json`). Ze worden gebouwd uit de OwnDesk-broncode en gecontroleerd met de ARM Template Test Toolkit.

# Плагин для работы acme.sh c dns провайдером 1cloud.ru

----
First you need to login to your account to get your API key from: https://panel.1cloud.ru/account/manage?pid=<id_account>#api-key.

Second, copy the file to one of acme's plugin file locations.

export OC_Key="<key>"

Ok, let's issue a cert now:

./acme.sh --issue --dns dns_1cloud -d example.com -d *.example.com

The SL_Key will be saved in ~/.acme.sh/account.conf and will be reused when needed.
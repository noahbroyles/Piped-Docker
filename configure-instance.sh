#!/bin/sh
echo "Enter a hostname for the Frontend (eg: piped.kavin.rocks):" && read -r frontend
echo "Enter a hostname for the Backend (eg: pipedapi.kavin.rocks):" && read -r backend
echo "Enter a hostname for the Proxy (eg: pipedproxy.kavin.rocks):" && read -r proxy
echo "Enter the reverse proxy you would like to use (caddy, nginx or standalone):" && read -r reverseproxy
echo "Is your hostname reachable via HTTP or HTTPS? (eg: https)" && read -r http_mode
echo "Enable automatic updates with Watchtower? Recommended, so new Piped releases and fixes are installed for you. (Y/n)" && read -r autoupdate

rm -rf config/
rm -f docker-compose.yml

cp -r template/ config/

conffiles=$(find config/ -type f ! -name '*.yml')
sed -i "s/FRONTEND_HOSTNAME/$frontend/g" $conffiles
sed -i "s/BACKEND_HOSTNAME/$backend/g" $conffiles
sed -i "s/PROXY_HOSTNAME/$proxy/g" $conffiles

sed -i "s/BACKEND_HOSTNAME_PLACEHOLDER/$backend/g" config/*.yml
sed -i "s/HTTP_MODE_PLACEHOLDER/$http_mode/g" config/*.yml $conffiles

mv config/docker-compose.$reverseproxy.yml docker-compose.yml

# Automatic updates stay on unless the answer starts with n; pressing Enter keeps the recommended default.
case "$autoupdate" in
    [nN]*)
        # The templates wrap the watchtower service in "# BEGIN watchtower" and "# END watchtower" comments.
        sed -i '/# BEGIN watchtower/,/# END watchtower/d' docker-compose.yml
        echo "Automatic updates are off. To update, run 'docker compose pull' and then 'docker compose up -d'."
        ;;
    *)
        echo "Automatic updates are on. Watchtower checks for new images once a day."
        ;;
esac

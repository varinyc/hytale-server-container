#!/bin/bash
set -e

mkdir -p /app/launcher
mkdir -p /app/data
cd /app

server_location="/app/data"
config_file="${server_location}/config.json"

launcher_location="/app/launcher"
launcher_file="${launcher_location}/hytale-downloader-linux-amd64"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" >&2; }

device_auth() {
  RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=hytale-server" \
    -d "scope=openid offline auth:server")

  device_code=$(echo "$RESPONSE" | jq -r '.device_code')
  user_code=$(echo "$RESPONSE" | jq -r '.user_code')
  verification_uri_complete=$(echo "$RESPONSE" | jq -r '.verification_uri_complete')
  interval=$(echo "$RESPONSE" | jq -r '.interval')

  log "Visit: $verification_uri_complete"

  while true; do
    sleep "$interval"

    TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=hytale-server" \
      -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      -d "device_code=$device_code")

    error=$(echo "$TOKEN_RESPONSE" | jq -r '.error')
    if [ "$error" = "authorization_pending" ]; then
      continue
    elif [ "$error" != "null" ] && [ -n "$error" ]; then
      log "Error: $error" >&2
      exit 1
    else
      refresh_token=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
      access_token=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
      jq --arg new_refresh_token "$refresh_token" '.refresh_token = $new_refresh_token' "${config_file}" > "/tmp/config_file.tmp" &&
      mv "/tmp/config_file.tmp" "${config_file}"
      break
    fi
  done
}

if [ -f "${config_file}" ]; then
    refresh_token=$(jq -r '.refresh_token' "$config_file" 2>/dev/null)
    game_version=$(jq -r '.game_version' "$config_file" 2>/dev/null)
else
  jq -n '{
    "game_version": null,
    "refresh_token": null
  }' > ${config_file}

  refresh_token=""
  game_version=""
fi

log "Checking for hytale-downloader..."
if [ ! -f "${launcher_file}" ]; then
  log "Retrieving hytale-downloader from website..."
  curl -L -o /tmp/hytale-downloader.zip https://downloader.hytale.com/hytale-downloader.zip
  unzip -j /tmp/hytale-downloader.zip "hytale-downloader-linux-amd64" -d "${launcher_location}"
  chmod +x "${launcher_file}"
fi

cd /app/launcher
log "Printing Hytale-Downloader versions to proc Interactive Session"
"${launcher_file}" -version
"${launcher_file}" -print-version

log "Clearing tmp files..."
rm -rf /tmp/*

log "Updating Game Version..."
new_game_version=`"${launcher_file}" -print-version`
log "Remote Version: ${new_game_version} // Local Version: ${game_version}"

if [ "${new_game_version}" != "${game_version}" ]; then
  log "Updating server files..."
  "${launcher_file}" -download-path /tmp/server.zip -skip-update-check

  log "Extracting server files..."
  unzip -o /tmp/server.zip -d "${server_location}"

  jq --arg version "$new_game_version" '.game_version = $version' "$config_file" > "/tmp/config_file.tmp"
  mv "/tmp/config_file.tmp" "${config_file}"
fi

log "Checking files for valid Refresh Token..."
if [ -n "$refresh_token" ] && [ "$refresh_token" != "null" ]; then
  log "Submitting current Refresh Token..."
  TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=hytale-server" \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$refresh_token")

  # Check if refresh token is still valid
  error=$(echo "$TOKEN_RESPONSE" | jq -r '.error')
  if [ "$error" = "invalid_grant" ] || [ "$error" = "invalid_token" ]; then
    log "Refresh Token invalid, requesting Device ID authentication..."
    device_auth
  else
    access_token=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    new_refresh=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
    if [ "$new_refresh" != "null" ] && [ -n "$new_refresh" ]; then
      jq --arg new_refresh_token "$new_refresh" '.refresh_token = $new_refresh_token' "${config_file}" > "/tmp/config_file.tmp"
      mv "/tmp/config_file.tmp" "${config_file}"
    fi
  fi
else
  log "No Refresh Token available, requesting Device ID authentication..."
  device_auth
fi

log "Requesting Profiles List..."
PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
  -H "Authorization: Bearer $access_token")

profile_uuid=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid')
SESSION_RESPONSE=$(curl -s -X POST "https://sessions.hytale.com/game-session/new" \
  -H "Authorization: Bearer $access_token" \
  -H "Content-Type: application/json" \
  -d "{\"uuid\": \"$profile_uuid\"}")

session_token=$(echo "$SESSION_RESPONSE" | jq -r '.sessionToken')
identity_token=$(echo "$SESSION_RESPONSE" | jq -r '.identityToken')

log "Starting Hytale server..."
log "Using memory: ${INIT_MEMORY} initial, ${MAX_MEMORY} max"


cd "${server_location}/Server"
if [ "${AOT}" = "true" ]; then
  exec java -Xmx${MAX_MEMORY} -Xms${INIT_MEMORY} -XX:AOTCache="${server_location}/Server/HytaleServer.aot" -jar "${server_location}/Server/HytaleServer.jar" --assets "${server_location}/Assets.zip" --session-token "${session_token}" --identity-token "${identity_token}"
else
  exec java -Xmx${MAX_MEMORY} -Xms${INIT_MEMORY} -jar "${server_location}/Server/HytaleServer.jar" --assets "${server_location}/Assets.zip" --session-token "${session_token}" --identity-token "${identity_token}"
fi


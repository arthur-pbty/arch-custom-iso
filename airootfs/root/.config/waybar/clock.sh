#!/usr/bin/env bash

print_status() {
  time=$(date +"%H:%M")
  date=$(date +"%d/%m")

  # tooltip complet
  full_date=$(date +"%A %d %B %Y %H:%M:%S")
  calendar=$(cal -m)
  esc_calendar=$(sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g' <<< "$calendar")

  text="$time
$date"

    tooltip="$full_date

$esc_calendar"

  jq -nc \
     --arg text "$text" \
     --arg tooltip "$tooltip" \
     '{ text: $text, tooltip: $tooltip }'
}

print_status

last=""

while true; do
  current=$(date +"%H%M%S%Y%m%d")

  if [[ "$current" != "$last" ]]; then
    print_status
    last="$current"
  fi

  sleep 1
done

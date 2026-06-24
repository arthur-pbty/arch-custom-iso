#!/bin/bash

PLAYER="subtui"

# Vérifie si Subtui est lancé
if ! playerctl -l 2>/dev/null | grep -q "^${PLAYER}$"; then
  echo '{"text":"󰝚","tooltip":"Subtui non lancé"}'
  exit 0
fi

# Métadonnées
title=$(playerctl -p "$PLAYER" metadata title 2>/dev/null)
artist=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null)
album=$(playerctl -p "$PLAYER" metadata album 2>/dev/null)
status=$(playerctl -p "$PLAYER" status 2>/dev/null)

# Valeurs par défaut
[ -z "$title" ] && title="Titre inconnu"
[ -z "$artist" ] && artist="Artiste inconnu"
[ -z "$album" ] && album="Album inconnu"

# Position actuelle (secondes)
position=$(playerctl -p "$PLAYER" position 2>/dev/null)
[ -z "$position" ] && position=0

# Durée totale (microsecondes)
length=$(playerctl -p "$PLAYER" metadata mpris:length 2>/dev/null)
[ -z "$length" ] && length=0

# Conversion sûre
position_sec=$(awk -v p="$position" 'BEGIN { printf("%d", p+0.5) }')
length_sec=$((length / 1000000))

# Format temps
elapsed=$(printf "%02d:%02d" $((position_sec/60)) $((position_sec%60)))

if [ "$length_sec" -gt 0 ]; then
  duration=$(printf "%02d:%02d" $((length_sec/60)) $((length_sec%60)))
else
  duration="--:--"
fi

# Icône
if [ "$status" = "Playing" ]; then
  icon="󰏤"
else
  icon="󰐊"
fi

# Échapper les guillemets pour JSON
title=${title//\"/\\\"}
artist=${artist//\"/\\\"}
album=${album//\"/\\\"}

# Tooltip
tooltip="$artist
$title

Album : $album

$elapsed / $duration

Clic gauche : Lecture/Pause
Clic droit : Suivant
Clic milieu : Précédent"

# Convertir les retours à la ligne pour JSON
tooltip=$(echo "$tooltip" | sed ':a;N;$!ba;s/\n/\\n/g')

# JSON final
printf '{"text":"%s","tooltip":"%s"}\n' "$icon" "$tooltip"

#!/bin/bash

PLAYER="subtui"

if playerctl -l 2>/dev/null | grep -q "^${PLAYER}$"; then
  playerctl -p "$PLAYER" play-pause
else
  ghostty -e subtui &
fi
#!/bin/sh
set -e

# Run migrations (if you have any)
# /app/bin/blokus_bomberman eval "BlokusBomberman.Release.migrate"

# Start the application
exec /app/bin/blokus_bomberman start

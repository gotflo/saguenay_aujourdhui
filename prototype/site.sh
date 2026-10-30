#!/bin/sh
# Le site de la démo : le prototype, avec l'en-tête d'une vraie page web.
set -e
cd "$(dirname "$0")/.."
mkdir -p site
{
  cat <<'HEAD'
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0);padding-bottom:env(safe-area-inset-bottom,0)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
HEAD
  grep -v 'claude:viewport-fit-sides' prototype/saguenay-aujourdhui.html
} > site/index.html

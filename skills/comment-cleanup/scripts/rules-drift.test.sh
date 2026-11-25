#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
skills="$here/../.."

short_form() {
  awk '/^<!-- comment-rules:start/ { on = 1; next } /^<!-- comment-rules:end/ { on = 0 } on' "$1"
}

source_form=$(short_form "$skills/comment-cleanup/RULES.md")
sees "RULES.md holds the short form" 'A comment that stays is one line' "$source_form"

for rubric in react-review angular-review nestjs-service-review spring-service-review go-service-review htmx-review; do
  eq "$rubric carries the short form word for word" "$(short_form "$skills/$rubric/CHECKLIST.md")" "$source_form"
done

finish

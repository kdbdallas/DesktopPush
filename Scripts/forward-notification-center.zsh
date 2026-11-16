#!/bin/zsh
# Polls the private macOS Notification Center database and forwards only
# notifications that are delivered after this script starts.
#
# Progress is tracked as a cursor of DELIVERED_MICROSECONDS:REC_ID rather than
# rec_id alone. The record table's rec_id is a plain INTEGER PRIMARY KEY, so
# SQLite reuses the highest ID whenever the newest notification is removed
# (clicked, dismissed, or cleared by its app). A rec_id watermark therefore
# silently skips the next notification after every such removal.

set -uo pipefail

: "${PUSH_P12:?Set PUSH_P12 to the path of the APNs .p12 file.}"
: "${P12_PASSWORD:?Set P12_PASSWORD to the .p12 password.}"

DESKTOPPUSH_BIN="${DESKTOPPUSH_BIN:-desktoppush}"
SQLITE_BIN="${SQLITE_BIN:-/usr/bin/sqlite3}"
POLL_INTERVAL="${NOTIFICATION_POLL_INTERVAL:-2}"
PUSH_TOPIC="${PUSH_TOPIC:-com.port21.desktoppush.iOS}"
NOTIFICATION_DATABASE="${NOTIFICATION_CENTER_DATABASE:-${HOME}/Library/Group Containers/group.com.apple.usernoted/db2/db}"
BATCH_LIMIT=20

# Keep in sync with NotificationCursor.deliveredMicrosecondsSQL in DesktopPushCLI.swift.
DELIVERED_US='CAST(ROUND(delivered_date * 1000000) AS INTEGER)'

log() {
    print -ru2 -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_query() {
    "${SQLITE_BIN}" -readonly -noheader "${NOTIFICATION_DATABASE}" "$1" 2>/dev/null
}

is_cursor() {
    [[ "$1" == <->:<-> ]]
}

latest_cursor() {
    local cursor
    cursor="$(run_query "SELECT COALESCE((SELECT ${DELIVERED_US} || ':' || rec_id FROM record WHERE delivered_date IS NOT NULL ORDER BY ${DELIVERED_US} DESC, rec_id DESC LIMIT 1), '0:0');")" || return 1
    is_cursor "${cursor}" || return 1
    print -r -- "${cursor}"
}

# Prints the cursors of up to BATCH_LIMIT delivered records after the given
# cursor, oldest first. Prints nothing when there are none.
next_cursors() {
    local after_cursor="$1"
    local delivered="${after_cursor%%:*}"
    local record_id="${after_cursor##*:}"
    run_query "SELECT ${DELIVERED_US} || ':' || rec_id FROM record WHERE delivered_date IS NOT NULL AND (${DELIVERED_US}, rec_id) > (${delivered}, ${record_id}) ORDER BY ${DELIVERED_US} ASC, rec_id ASC LIMIT ${BATCH_LIMIT};"
}

wait_for_database() {
    local cursor
    while true; do
        if cursor="$(latest_cursor)"; then
            print -r -- "${cursor}"
            return
        fi
        log "Notification Center database is unavailable. Grant Full Disk Access to the terminal running this script, then retrying in ${POLL_INTERVAL}s."
        sleep "${POLL_INTERVAL}"
    done
}

last_cursor="$(wait_for_database)"
log "Watching Notification Center after cursor ${last_cursor}."
database_failure_count=0

while true; do
    sleep "${POLL_INTERVAL}"

    if ! batch_output="$(next_cursors "${last_cursor}")"; then
        (( database_failure_count += 1 ))
        if (( database_failure_count == 1 || database_failure_count % 30 == 0 )); then
            log "Cannot read the Notification Center database. Grant Full Disk Access to the terminal running this script; retrying in ${POLL_INTERVAL}s."
        fi
        continue
    fi
    database_failure_count=0

    [[ -n "${batch_output}" ]] || continue
    cursors=("${(@f)batch_output}")
    through_cursor="${cursors[-1]}"
    if ! is_cursor "${through_cursor}"; then
        log "Ignoring unexpected database output: ${through_cursor}"
        continue
    fi

    batch_size=${#cursors}
    if (( batch_size == 1 )); then
        entry_label="entry"
    else
        entry_label="entries"
    fi
    log "Forwarding ${batch_size} Notification Center ${entry_label} through cursor ${through_cursor}."

    if "${DESKTOPPUSH_BIN}" notification-center \
        --certificate "${PUSH_P12}" \
        --password "${P12_PASSWORD}" \
        --topic "${PUSH_TOPIC}" \
        --broadcast \
        --after-cursor "${last_cursor}" \
        --through-cursor "${through_cursor}" \
        --limit "${batch_size}"; then
        last_cursor="${through_cursor}"
    else
        log "Forwarding failed; the same records will be retried on the next poll."
    fi
done

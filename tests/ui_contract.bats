#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "UI helper keeps sourcing side-effect free and honors color controls" {
    run bash -c 'source "$1/lib/shell_tools_ui.sh"; [[ -z "${ST_UI_COLOR+x}" ]]' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]

    run bash -c 'source "$1/lib/shell_tools_ui.sh"; st_ui_init never; st_ok ready' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK] ready"* ]]
    [[ "$output" != *$'\033['* ]]

    run env NO_COLOR=1 bash -c 'source "$1/lib/shell_tools_ui.sh"; st_ui_init always; st_ok ready' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033['* ]]

    run env TERM=dumb bash -c 'source "$1/lib/shell_tools_ui.sh"; st_ui_init always; st_ok ready' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033['* ]]

    run env NO_COLOR=1 TERM=dumb bash -c 'source "$1/lib/shell_tools_ui.sh"; st_ui_init never; st_ok ready' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033['* ]]

    run bash -c 'source "$1/lib/shell_tools_ui.sh"; st_ui_init always; st_ok ready' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033['* ]]
}

@test "health snapshot JSON remains parseable and stdout-only" {
    run "$REPO_ROOT/system_health_snapshot.sh" --format json
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033['* ]]
    node -e 'JSON.parse(process.argv[1])' "$output"
}

@test "health snapshot strict mode reports unavailable proc inputs" {
    run env ST_HEALTH_PROC_ROOT="$BATS_TEST_TMPDIR/missing-proc" "$REPO_ROOT/system_health_snapshot.sh" --format json --strict
    [ "$status" -eq 1 ]
    node -e 'const v=JSON.parse(process.argv[1]); if (!v.warnings.length) process.exit(1)' "$output"
}

@test "health snapshot validates arguments without collecting data" {
    run "$REPO_ROOT/system_health_snapshot.sh" --format xml
    [ "$status" -eq 2 ]
    [[ "$output" == *"无效输出格式"* ]]
}
